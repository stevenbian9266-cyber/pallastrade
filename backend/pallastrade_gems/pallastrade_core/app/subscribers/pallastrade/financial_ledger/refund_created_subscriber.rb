# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-3 (PRD-20260906-payments-fin-p4-3)
#
# FinancialLedger::RefundCreatedSubscriber —— refund.created → PostRefund 接线（FR-4P3-05/07）。
#
# 事件源：Refund `publishes_lifecycle_events` after_commit 发布 `refund.created`
#   （automatic lifecycle 事件：写入失败不触发；Refund 创建提交 = perform! 成功——失败 raise 回滚）
#   → posting 恒在退款事务提交后执行（P4 §16）。
#
# 可靠性：subscriber 默认 async（SubscriberJob）；PostRefund 幂等 → 重试不重复 posting。
# 健壮性：payload id 支持 prefixed（re_）或 raw integer 双模式；解析失败/异常 rescue → 日志（不阻断退款流）。
module PallasTrade
  module FinancialLedger
    class RefundCreatedSubscriber < PallasTrade::Subscriber
      subscribes_to 'refund.created'

      def handle(event)
        refund = find_refund(event.payload)
        return if refund.nil?

        result = PallasTrade::FinancialLedger::PostRefund.call(refund: refund)
        return unless result.success?
        return unless result.value[:skipped]

        Rails.logger.info(
          "[FinancialLedger::RefundCreatedSubscriber] skip ledger posting for refund #{refund.prefixed_id}: #{result.value[:reason]}"
        )
      rescue StandardError => e
        Rails.logger.error(
          "[FinancialLedger::RefundCreatedSubscriber] ledger posting failed for refund #{refund&.prefixed_id}: #{e.class} #{e.message}"
        )
      end

      private

      # refund.created payload 走 event_payload（RefundSerializer 或 minimal fallback，均含 prefixed id）。
      def find_refund(payload)
        id = payload.try(:[], 'id') || payload.try(:[], :id)
        return if id.blank?

        if id.to_s.start_with?('re_')
          PallasTrade::Refund.find_by_param(id)
        else
          PallasTrade::Refund.find_by(id: id)
        end
      end
    end
  end
end
