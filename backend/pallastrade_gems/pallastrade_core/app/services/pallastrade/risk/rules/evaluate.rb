# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片2（PRD-20260917-payments-d15b-risk-rules；业务方案 §72.2）——
# `Risk::Rules::Evaluate` —— **规则求值**（生效版本 + 灰度分桶 + 首个命中）。
#
# 语义（唯一权威）：
#   * 规则集选择：**本店铺规则集优先，其次全局**（更具体者胜；同 code 不叠加）；
#   * 参与条件：规则集 `status == 'active'` 且有 `active_version_id`（否则返回 nil，**不猜**）；
#   * 灰度：`canary_version_id` 存在且 `canary_percent > 0` 时，
#     桶 = `SHA256("<rule_set_id>:<order 标识>")` 前 8 位十六进制对 100 取模；
#     桶 < percent → 金丝雀版，否则稳定版；percent = 0 恒稳定版、≥ 100 恒金丝雀；
#     桶只由（规则集, 订单）决定 → **跨请求/跨天恒定**，可复算；
#   * 求值：按 `priority` 升序（同优先级按数组序）取**首个命中**（与既有 `Risk.evaluate` 一致）；
#   * **只读**：零写库、零 provider、不改订单 —— 写留痕由 `Risk::Assess` 负责。
#
# 返回 payload（`Risk::Assess` 直接写进留痕 `signals['rule_engine']`）：
#   { rule_set_id:, rule_set_code:, version:, canary:, bucket:, rule_code:, action:,
#     matched_conditions:, skipped: [] }
#   `rule_code: nil` 表示「该版本被求值但无规则命中」（同样是可解释的事实）。
module PallasTrade
  module Risk
    module Rules
      class Evaluate
        prepend PallasTrade::ServiceModule::Base

        BUCKET_RANGE = 100

        # @param order [PallasTrade::Order]
        # @param now [Time]
        # @return [PallasTrade::ServiceModule::Result] success(Hash | nil)
        def call(order:, now: Time.current)
          return success(nil) if order.nil?

          @order = order
          @now = now

          rule_set = effective_rule_set
          return success(nil) if rule_set.nil?

          version, canary, bucket = effective_version(rule_set)
          return success(nil) if version.nil?

          evaluate_rules(rule_set, version, canary, bucket)
        rescue StandardError => e
          Rails.logger.error("[Risk::Rules::Evaluate] failed for order #{order&.id}: #{e.class} #{e.message}")
          success(nil)
        end

        private

        # 本店铺优先，其次全局（同 code 不叠加：更具体者胜）
        def effective_rule_set
          store_id = @order.respond_to?(:store_id) ? @order.store_id : nil
          scope = PallasTrade::RiskRuleSet.active
          scoped = store_id.present? ? scope.where(store_id: store_id) : scope.none
          scoped.recent_first.first || scope.global.recent_first.first
        end

        # @return [Array(RiskRuleVersion, Boolean, Integer)]
        def effective_version(rule_set)
          stable = rule_set.versions.find_by(id: rule_set.active_version_id)
          return [nil, false, nil] if stable.nil? && rule_set.canary_version_id.blank?

          bucket = bucket_for(rule_set)
          if rule_set.canary_active? && bucket < rule_set.canary_percent.to_i
            canary_version = rule_set.versions.find_by(id: rule_set.canary_version_id)
            # 只认**已发布**的金丝雀版本（草稿/归档→回落稳定版，不猜）
            return [canary_version, true, bucket] if canary_version&.published?
          end

          [stable, false, bucket]
        end

        # 桶只由（规则集, 订单）决定 —— 稳定、可复算、与时间无关
        def bucket_for(rule_set)
          digest = ::Digest::SHA256.hexdigest("#{rule_set.id}:#{order_token}")
          digest[0, 8].to_i(16) % BUCKET_RANGE
        end

        def order_token
          if @order.respond_to?(:prefixed_id) && @order.prefixed_id.present?
            @order.prefixed_id
          else
            @order.id.to_s
          end
        end

        def evaluate_rules(rule_set, version, canary, bucket)
          skipped = []
          matched_conditions = nil

          hit = sorted_rules(version).find do |rule|
            outcome = Condition.call(order: @order, conditions: rule['conditions'], now: @now).value
            skipped.concat(Array(outcome[:skipped]))
            matched_conditions = rule['conditions'] if outcome[:matched]
            outcome[:matched]
          end

          success(
            rule_set_id: rule_set.id,
            rule_set_code: rule_set.code,
            version: version.version,
            canary: canary,
            bucket: bucket,
            rule_code: hit && hit['code'],
            action: hit && hit['action'],
            matched_conditions: matched_conditions,
            skipped: skipped.uniq
          )
        end

        # priority 升序；同优先级保持数组序（稳定）
        def sorted_rules(version)
          Array(version.rules).each_with_index
                              .sort_by { |rule, index| [rule['priority'].to_i, index] }
                              .map(&:first)
        end
      end
    end
  end
end
