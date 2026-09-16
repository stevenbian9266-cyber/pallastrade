# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.2 底座 / §72.3）——
# `Risk::Assess` —— 订单风控评估的**唯一入口**：名单命中 → 决策 → 留痕。
#
# 语义（保守 + 可追溯）：
#   * 先算 `allowlist`：命中即 `allow` 并**短路**（白名单优先于黑名单）；
#   * 再算 `denylist`：命中 → 决策取 `PallasTrade::Config[:risk_denylist_action]`（**默认 `review`**：
#     只标记待人工复核，绝不自动阻断；仅显式配置为 `block` 才是 `block`）；
#   * 无命中 / 主体不足（订单没有可比对的主体）→ `allow`（**不猜**）+ `signals['insufficient_subject']`；
#   * **每次评估落一行留痕**（`PaymentRiskAssessment`），幂等键 `(order_id, evaluated_at 秒)`；
#   * 本服务**不阻断、不改订单/支付状态、不调 provider**（处置留给后续切片）。
#
# 店铺隔离（硬边界）：只命中「全局名单（store_id IS NULL）+ 本订单所属店铺名单」。
module PallasTrade
  module Risk
    class Assess
      prepend PallasTrade::ServiceModule::Base

      DEFAULT_DENYLIST_ACTION = 'review'
      DENYLIST_ACTIONS = %w[review block].freeze
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

        decision, hits, signals = decide(subjects, allow_hits, order)

        assessment = find_reusable(order, decision, hits) || record_assessment(order, decision, hits, signals, evaluated_at)
        record_audit(order, decision, hits, signals) if PallasTrade::PaymentRiskAssessment::FLAGGED_DECISIONS.include?(decision)

        success({
          decision: decision,
          assessment: assessment,
          matched: hits.map(&:id),
          matched_summary: hits.map { |entry| summary_for(entry) },
          allowlisted: allow_hits.any?,
          denylisted: allow_hits.empty? && hits.any?,
          signals: signals
        })
      end

      private

      def decide(subjects, allow_hits, order)
        if allow_hits.any?
          ['allow', allow_hits, signals_for(subjects).merge('allowlisted' => true)]
        else
          deny_hits = matches(order, subjects, 'denylist')
          decision = deny_hits.any? ? denylist_action : 'allow'
          signals = signals_for(subjects).merge('denylisted' => deny_hits.any?, 'denylist_action' => denylist_action)
          [decision, deny_hits, signals]
        end
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
      def record_assessment(order, decision, hits, signals, evaluated_at)
        PallasTrade::PaymentRiskAssessment.create!(
          order_id: order.id,
          store_id: order.respond_to?(:store_id) ? order.store_id : nil,
          decision: decision,
          matched_entry_ids: hits.map(&:id),
          signals: signals,
          evaluated_at: evaluated_at,
          metadata: { 'matched' => hits.map { |entry| summary_for(entry) } }
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
