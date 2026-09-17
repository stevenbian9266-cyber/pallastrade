# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片3（PRD-20260917-checkout-d15-切片3；业务方案 §72.1 / §78-D15）——
# `Payments::ThreeDSecure::Required` —— 「**这一单要不要做 3DS/SCA 认证**」的**唯一判定入口**。
#
# 输入：门店策略（`ThreeDSecure::Policy`）+ 该订单**最近一次**风控决策（`PaymentRiskAssessment`）
#       + 订单本地事实（金额 / 币种 / 国家）。
# 输出（可解释，全部可断言）：
#   { required:, mode:, source:, reason:, exemptions:, exemption_policy:, risk_action:,
#     threshold_used:, threshold_skipped:, evaluated_at: }
#
# 语义（写死，勿在别处重算）：
#   * `always`     → 是（豁免可放宽到否）；
#   * `risk_based`（默认）→ 仅当风险决策 = `force_3ds` 时为是（豁免同样生效）；
#   * `off`        → 否 —— **但**风险明确 `force_3ds` 时风险优先（`policy_off_overridden_by='risk_rule'`）；
#     此时**不评估豁免**（`exemption_policy='skipped_mode_off'`）：运营显式关掉了挑战，
#     只有一条**显式规则**能把它打开，不能被「低金额/国家白名单」这类策略侧放宽项悄悄抵消。
#   * 豁免只放宽「**是否挑战**」，**绝不**放宽「是否可付」——`block` 决策不被豁免改写（本切片不改阻断语义）。
#   * 币种安全：低金额阈值**只在订单币种 == 门店默认币种**时参与比较，否则视为未配置
#     （`threshold_skipped='currency_mismatch'`）—— 不跨币种猜。
#
# 铁律：本服务**只读**（零写库、零 provider、零资金副作用）；留痕由 `Risk::Assess` / 建会话侧承担。
module PallasTrade
  module Payments
    module ThreeDSecure
      class Required
        prepend PallasTrade::ServiceModule::Base

        RISK_ACTION = 'force_3ds'

        EXEMPTION_LOW_AMOUNT = 'low_amount'
        EXEMPTION_COUNTRY = 'country_allowlisted'
        EXEMPTION_OPTION = 'option_allowlisted'

        SOURCE_POLICY = 'policy'
        SOURCE_RISK = 'risk_rule'
        SOURCE_BOTH = 'policy+risk'
        SOURCE_NONE = 'none'

        REASON_ALWAYS = 'mode_always'
        REASON_RISK_FORCED = 'risk_rule_force_3ds'
        REASON_OFF = 'mode_off'
        REASON_OFF_OVERRIDDEN = 'mode_off_overridden_by_risk_rule'
        REASON_NO_RISK = 'mode_risk_based_no_risk_signal'
        REASON_EXEMPTED = 'exempted'

        class << self
          # 便捷入口（仓库既有 `X.call` 风格）
          def call(**kwargs) = new.call(**kwargs)

          # 请求内**复用**判定：Resolver 会被逐 provider/逐入口调用，重复查询会放大到 N 次。
          # 缓存以「最新留痕（id, decision）」为指纹：
          #   * 指纹不变 → 直接用缓存（不再查策略/订单）；
          #   * 来了新留痕 → 自动失效重算（**不会**因为缓存而读到旧决策）；
          #   * 每调用 1 条轻量查询，与入口数量无关（NFR：查询数不随入口数增长）。
          # @param order [PallasTrade::Order]
          # @return [Hash] 判定结果（失败时返回安全默认：不要求认证）
          def for_order(order, store: nil, force: false)
            return SAFE_DEFAULT if order.nil?

            key = fingerprint(order)
            cached = order.instance_variable_get(:@three_d_secure_requirement)
            return cached[:value] if cached.present? && cached[:key] == key && !force

            outcome = call(order: order, store: store)
            value = outcome.success? ? outcome.value : SAFE_DEFAULT
            order.instance_variable_set(:@three_d_secure_requirement, { key: key, value: value })
            value
          end

          # 订单上的判定缓存失效（评估/策略变化后显式调用；测试与后台预览用）
          def reset_cache_for(order)
            order&.remove_instance_variable(:@three_d_secure_requirement) if
              order&.instance_variable_defined?(:@three_d_secure_requirement)
          end

          # 最新留痕指纹 `[id, decision]`（无留痕 → `[nil, nil]`）
          def fingerprint(order)
            return [nil, nil] unless order.respond_to?(:risk_assessments)

            order.risk_assessments.limit(1).pluck(:id, :decision).first || [nil, nil]
          end
        end

        SAFE_DEFAULT = {
          required: false, mode: Policy::DEFAULT_MODE, source: SOURCE_NONE, reason: REASON_NO_RISK,
          exemptions: [], exemption_policy: nil, risk_action: nil, threshold_used: nil,
          threshold_skipped: nil, evaluated_at: nil
        }.freeze

        # @param order [PallasTrade::Order]
        # @param store [PallasTrade::Store, nil] 缺省取 `order.store`
        # @param risk_action [String, nil] 显式风险决策（`Assess` 刚算出的决策尚未落留痕时使用，
        #   避免读到上一轮的旧行；缺省从留痕读）
        # @param now [Time]
        # @return [PallasTrade::ServiceModule::Result]
        def call(order:, store: nil, risk_action: nil, now: Time.current)
          return failure(nil, 'Order is required') if order.nil?

          store = store || order.try(:store)
          policy = Policy.for(store)
          risk_action = latest_risk_action(order) if risk_action.nil?
          risk_forces = risk_action.to_s == RISK_ACTION

          # `risk_based` 模式下，**策略本身不要求认证**（要求来自风险规则）→ source = risk_rule；
          # `always` 才是「策略要求」；`off` 策略要求为假（仅在风险显式要求时才是真）。
          policy_required = policy.always?

          required = policy_required || risk_forces
          result = {
            required: required,
            mode: policy.mode,
            source: source_for(policy_required, risk_forces),
            reason: reason_for(policy, policy_required, risk_forces),
            exemptions: [],
            exemption_policy: nil,
            risk_action: risk_action,
            policy_off_overridden_by: (policy.off? && risk_forces ? SOURCE_RISK : nil),
            policy_reasons: policy.reasons,
            threshold_used: nil,
            threshold_skipped: nil,
            evaluated_at: now
          }

          if required
            if policy.off?
              result[:exemption_policy] = 'skipped_mode_off'
            else
              exemptions, threshold_used, threshold_skipped = exemptions_for(order, store, policy)
              result[:exemptions] = exemptions
              result[:threshold_used] = threshold_used
              result[:threshold_skipped] = threshold_skipped
              if exemptions.any?
                result[:required] = false
                result[:reason] = REASON_EXEMPTED
              end
            end
          end

          success(result)
        end

        private

        # 最近一次留痕的决策（**已存在**的评估结果；本服务不触发评估）
        # 关联名 = `Order#risk_assessments`（D15 切片1 定义，默认按 evaluated_at 倒序）
        def latest_risk_action(order)
          return nil unless order.respond_to?(:risk_assessments)

          assessment = order.risk_assessments.recent_first.first
          assessment&.decision
        end

        def source_for(policy_required, risk_forces)
          return SOURCE_BOTH if policy_required && risk_forces
          return SOURCE_RISK if risk_forces
          return SOURCE_POLICY if policy_required

          SOURCE_NONE
        end

        def reason_for(policy, policy_required, risk_forces)
          return REASON_OFF_OVERRIDDEN if policy.off? && risk_forces
          return REASON_ALWAYS if policy.always? && policy_required
          return REASON_RISK_FORCED if risk_forces
          return REASON_OFF if policy.off?

          REASON_NO_RISK
        end

        # 三类豁免（业务方案 §72.1）。返回 [符合的豁免列表, 使用的阈值, 阈值跳过原因]
        def exemptions_for(order, store, policy)
          matched = []
          threshold_used = nil
          threshold_skipped = nil

          if policy.low_amount_threshold.present?
            if same_currency?(order, store)
              threshold_used = policy.low_amount_threshold
              amount = order.total.to_d
              matched << EXEMPTION_LOW_AMOUNT if amount < policy.low_amount_threshold
            else
              threshold_skipped = 'currency_mismatch'
            end
          end

          matched << EXEMPTION_COUNTRY if country_allowlisted?(order, policy)
          matched << EXEMPTION_OPTION if policy.allowlisted_option_kinds.any?

          [matched, threshold_used, threshold_skipped]
        end

        def same_currency?(order, store)
          order_currency = order.currency.to_s.upcase
          store_currency = store.try(:default_currency).to_s.upcase
          order_currency.present? && store_currency.present? && order_currency == store_currency
        end

        def country_allowlisted?(order, policy)
          return false if policy.allowlisted_countries.empty?

          country = order.ship_address&.country_iso.presence || order.bill_address&.country_iso.presence
          return false if country.blank?

          policy.allowlisted_countries.include?(country.to_s.upcase)
        end
      end
    end
  end
end
