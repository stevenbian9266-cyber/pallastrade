# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.2 底座 / §72.3）——
# `Risk::Assess` —— 订单风控评估的**唯一入口**：名单 + 规则引擎 → 决策 → 留痕。
#
# 语义（保守 + 可追溯）：
#   * 先算 `allowlist`：命中即 `allow` 并**短路**（人工白名单优先于一切）；
#   * 再算 `denylist`：命中 → 动作取 `PallasTrade::Config[:risk_denylist_action]`（**默认 `review`**：
#     只标记待人工复核，绝不自动阻断；仅显式配置为 `block` 才是 `block`）；
#   * **D15 切片2**：再算数据驱动规则引擎（`Risk::Rules::Evaluate`，版本化 + 灰度），
#     最终决策 = 「名单动作 vs 规则动作」**取最严者**（allow < review < block）——
#     保守方向：规则不得把名单判定放宽；
#   * 无命中 / 主体不足（订单没有可比对的主体）→ `allow`（**不猜**）+ `signals['insufficient_subject']`；
#   * **每次评估落一行留痕**（`PaymentRiskAssessment`），幂等键 `(order_id, evaluated_at 秒)`；
#     规则引擎的版本/金丝雀/桶/命中规则写进 `signals['rule_engine']` 与 `metadata['rule_engine']`（jsonb，零迁移）；
#   * 本服务**不阻断、不改订单/支付状态、不调 provider**（处置沿用既有「标记人工复核」路径与后续切片）。
#
# 店铺隔离（硬边界）：只命中「全局名单（store_id IS NULL）+ 本订单所属店铺名单」。
module PallasTrade
  module Risk
    class Assess
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_DENYLIST_ACTION = 'review'
      DENYLIST_ACTIONS = %w[review block].freeze
      # 决策严重度（唯一口径）：取最严者，且规则不得放宽名单判定
      # D15 切片3：`force_3ds`（强制认证）比 `review` 严、比 `block` 轻 —— 既不阻断成交，也不放过风险。
      DECISION_SEVERITY = { 'allow' => 0, 'review' => 1, 'force_3ds' => 2, 'block' => 3 }.freeze
      # 重复投递去重窗口：同一订单**相同决策 + 相同命中集**在窗口内复用已有留痕行
      # （真正的再次评估（窗口之外 / 决策或命中变了）仍会新增一行，审计链路不丢）
      REUSE_WINDOW = 5.minutes

      # @param order [PallasTrade::Order]
      # @param now [Time]
      # @return [PallasTrade::ServiceModule::Result] success(Hash) / failure(nil, message)
      def call(order:, now: Time.current)
        return failure(nil, 'Order is required') if order.nil?

        evaluated_at = now.change(usec: 0)
        subjects = subjects_for(order)
        allow_hits = matches(order, subjects, 'allowlist')
        # D15 切片2：规则引擎（版本化/灰度）——只读求值，结果并入决策与留痕
        rule_result = PallasTrade::Risk::Rules::Evaluate.call(order: order, now: now).value

        decision, hits, signals = decide(subjects, allow_hits, order, rule_result)
        signals = signals.merge('three_d_secure' => three_d_secure_signal(order, decision))

        assessment = find_reusable(order, decision, hits) ||
                     record_assessment(order, decision, hits, signals, evaluated_at, rule_result)
        if PallasTrade::PaymentRiskAssessment::FLAGGED_DECISIONS.include?(decision)
          record_audit(order, decision, hits, signals)
        end

        success({
                  decision: decision,
                  assessment: assessment,
                  matched: hits.map(&:id),
                  matched_summary: hits.map { |entry| summary_for(entry) },
                  allowlisted: allow_hits.any?,
                  denylisted: allow_hits.empty? && hits.any?,
                  signals: signals,
                  rule_engine: rule_result
                })
      end

      private

      # 决策合并（唯一口径）：白名单**短路**优先；否则「名单动作 vs 规则动作」取**最严**者。
      def decide(subjects, allow_hits, order, rule_result)
        base = signals_for(subjects).merge('rule_engine' => rule_signal(rule_result))

        if allow_hits.any?
          signals = base.merge('allowlisted' => true, 'rule_engine_overridden_by' => 'allowlist')
          return ['allow', allow_hits, signals]
        end

        deny_hits = matches(order, subjects, 'denylist')
        list_action = deny_hits.any? ? denylist_action : 'allow'
        rule_action = rule_result && rule_result[:action].to_s.presence
        decision = strictest_action(list_action, rule_action)
        signals = base.merge(
          'denylisted' => deny_hits.any?,
          'denylist_action' => list_action,
          'rule_action' => rule_action,
          'decision_source' => decision_source(list_action, rule_action, decision)
        )
        [decision, deny_hits, signals]
      end

      def strictest_action(list_action, rule_action)
        return list_action if rule_action.blank?

        [list_action, rule_action].max_by { |action| DECISION_SEVERITY.fetch(action.to_s, 1) }
      end

      def decision_source(list_action, rule_action, decision)
        return 'denylist' if list_action == decision && rule_action != decision
        return 'rule_engine' if rule_action == decision && list_action != decision

        'both'
      end

      # D15 切片3（PRD-20260917-checkout-d15-切片3）：认证需求留痕（可解释：为什么本单会被要求 3DS）。
      # 用**本轮刚算出的决策**作为 `risk_action`（留痕尚未落库，不能去读上一轮旧行）。
      # 同时使订单上的判定缓存失效，使同一请求内接下来的可用性求值拿到最新结论。
      def three_d_secure_signal(order, decision)
        outcome = PallasTrade::Payments::ThreeDSecure::Required.call(order: order, risk_action: decision)
        PallasTrade::Payments::ThreeDSecure::Required.reset_cache_for(order)
        return { 'evaluated' => false } unless outcome.success?

        value = outcome.value
        {
          'evaluated' => true,
          'required' => value[:required],
          'mode' => value[:mode],
          'source' => value[:source],
          'reason' => value[:reason],
          'exemptions' => value[:exemptions],
          'exemption_policy' => value[:exemption_policy],
          'risk_action' => value[:risk_action],
          'policy_off_overridden_by' => value[:policy_off_overridden_by],
          'threshold_used' => value[:threshold_used]&.to_s,
          'threshold_skipped' => value[:threshold_skipped]
        }
      end

      # 规则引擎留痕（可解释性：用了哪一套规则的哪一版、是否金丝雀、桶、命中哪条、跳过了什么）
      def rule_signal(rule_result)
        return { 'consulted' => false } if rule_result.blank?

        {
          'consulted' => true,
          'rule_set_id' => rule_result[:rule_set_id],
          'rule_set_code' => rule_result[:rule_set_code],
          'version' => rule_result[:version],
          'canary' => rule_result[:canary],
          'bucket' => rule_result[:bucket],
          'rule_code' => rule_result[:rule_code],
          'action' => rule_result[:action],
          'matched_conditions' => rule_result[:matched_conditions],
          'skipped' => Array(rule_result[:skipped])
        }
      end

      # 只解析**本地可得**的主体（零 provider I/O）；缺失主体不猜
      # @return [Hash] { subject_type => [values] }
      def subjects_for(order)
        {
          'email' => [order.email].compact_blank,
          'ip' => [order.respond_to?(:last_ip_address) ? order.last_ip_address : nil].compact_blank,
          'customer' => order.respond_to?(:user_id) && order.user_id.present? ? [order.user_id.to_s] : [],
          'country' => [billing_country(order)].compact_blank
        }
      end

      def billing_country(order)
        address = order.respond_to?(:bill_address) ? order.bill_address : nil
        return nil if address.nil?

        address.country&.iso
      rescue StandardError
        nil
      end

      # 命中查询：一次 `IN` 查询（有界）；只取「全局 + 本店」的生效行
      def matches(order, subjects, list_type)
        hashes = subjects.flat_map do |subject_type, values|
          values.map do |value|
            PallasTrade::PaymentRiskList.value_hash_for(list_type: list_type, subject_type: subject_type, value: value)
          end
        end.uniq
        return [] if hashes.empty?

        PallasTrade::PaymentRiskList.where(list_type: list_type, value_hash: hashes)
                                    .for_store(order.respond_to?(:store) ? order.store : nil)
                                    .active
                                    .to_a
      end

      def signals_for(subjects)
        {
          'subject_types' => subjects.keys,
          'subject_count' => subjects.values.flatten.size,
          'insufficient_subject' => subjects.values.flatten.empty?
        }
      end

      # @return [String] 决策动作（默认保守 review；非法配置回落默认）
      def denylist_action
        configured = PallasTrade::Config[:risk_denylist_action].to_s.downcase
        DENYLIST_ACTIONS.include?(configured) ? configured : DEFAULT_DENYLIST_ACTION
      end

      # 幂等（重复投递）：窗口内「同决策 + 同命中集」直接复用已有留痕行
      def find_reusable(order, decision, hits)
        signature = hits.map(&:id).sort
        PallasTrade::PaymentRiskAssessment
          .where(order_id: order.id, decision: decision)
          .where(evaluated_at: REUSE_WINDOW.ago..)
          .recent_first
          .detect { |candidate| candidate.matched_entry_ids.sort == signature }
      end

      # 幂等（并发兼底）：同一订单同一秒只落一行
      def record_assessment(order, decision, hits, signals, evaluated_at, rule_result = nil)
        PallasTrade::PaymentRiskAssessment.create!(
          order_id: order.id,
          store_id: order.respond_to?(:store_id) ? order.store_id : nil,
          decision: decision,
          matched_entry_ids: hits.map(&:id),
          signals: signals,
          evaluated_at: evaluated_at,
          metadata: { 'matched' => hits.map { |entry| summary_for(entry) },
                      'rule_engine' => rule_signal(rule_result) }
        )
      rescue ActiveRecord::RecordNotUnique
        PallasTrade::PaymentRiskAssessment.find_by(order_id: order.id, evaluated_at: evaluated_at)
      end

      def summary_for(entry)
        {
          'id' => entry.id,
          'list_type' => entry.list_type,
          'subject_type' => entry.subject_type,
          'masked' => entry.masked_value
        }
      end

      def record_audit(order, decision, hits, signals)
        PallasTrade::Audit.record(
          action: 'risk_order_flagged',
          actor: 'system',
          resource: order,
          after: {
            decision: decision,
            matched_count: hits.size,
            matched: hits.map { |entry| summary_for(entry) },
            signals: signals
          }
        )
      rescue StandardError => e
        Rails.logger.error("[Risk::Assess] audit failed for order #{order&.prefixed_id}: #{e.class} #{e.message}")
      end
    end
  end
end
