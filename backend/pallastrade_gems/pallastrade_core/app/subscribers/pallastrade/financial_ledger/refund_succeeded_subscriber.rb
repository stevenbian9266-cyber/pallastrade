# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-1 (PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation)
#
# FinancialLedger::RefundSucceededSubscriber —— refund.succeeded → PostRefund 接线。
# （原 refund.created → PostRefund 在 REV-P6-1 后语义不再成立：Refund 创建 = durable
#   REQUESTED，不再隐含 provider 成功——见 refund.rb 状态机与 Refunds::Execute。）
#
# 事件源：Refund state 迁移到 succeeded 的 after_commit 发布 `refund.succeeded`
#   （提交后触发 → posting 恒在退款资金事务提交后执行，对齐 payment.paid 模式）。
# 守卫：仅 SUCCEEDED 的 Refund 进入 PostRefund（ResolveRefund → REFUND_SUCCEEDED）；
#   failed/ambiguous/requested/processing 绝不产生 REFUND_SUCCEEDED journal entry（AC-6013/6014）。
#
# 可靠性：subscriber 默认 async（PallasTrade::Events::SubscriberJob）；PostRefund 幂等
#   （FinancialLedger::Post idempotency_key）→ 重试不重复 posting。
# 健壮性：payload id 支持 prefixed（re_）或 raw integer 双模式；解析失败/异常 rescue → 日志。
module PallasTrade
  module FinancialLedger
    class RefundSucceededSubscriber < PallasTrade::Subscriber
      subscribes_to 'refund.succeeded'

      def handle(event)
        refund = find_refund(event.payload)
        return if refund.nil?
        return unless refund.succeeded?

        result = PallasTrade::FinancialLedger::PostRefund.call(refund: refund)
        return unless result.success?
        return unless result.value[:skipped]

        Rails.logger.info(
          "[FinancialLedger::RefundSucceededSubscriber] skip ledger posting for refund #{refund.prefixed_id}: #{result.value[:reason]}"
        )
      rescue StandardError => e
        Rails.logger.error(
          "[FinancialLedger::RefundSucceededSubscriber] ledger posting failed for refund #{refund&.prefixed_id}: #{e.class} #{e.message}"
        )
      end

      private

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
