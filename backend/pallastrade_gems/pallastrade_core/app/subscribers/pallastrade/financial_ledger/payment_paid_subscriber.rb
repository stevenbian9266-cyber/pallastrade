# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-3 (PRD-20260906-payments-fin-p4-3)
#
# FinancialLedger::PaymentPaidSubscriber —— payment.paid → PostPayment 接线（FR-4P3-04/07）。
#
# 事件源：Payment::CustomEvents after_commit on update state→completed 发布 `payment.paid`
#   （提交后触发 → posting 恒在资金事务提交后执行，P4 §16：ledger 失败不逆转支付）。
#
# 可靠性：subscriber 默认 async（PallasTrade::Events::SubscriberJob）；PostPayment 幂等
#   （FinancialLedger::Post idempotency_key）→ 重试不重复 posting。
# 健壮性：payload id 支持 prefixed（py_）或 raw integer 双模式（参照 PaymentSessionReservationSubscriber）；
#   解析失败/异常 rescue → Rails.logger（不阻断 payment 流）。
module PallasTrade
  module FinancialLedger
    class PaymentPaidSubscriber < PallasTrade::Subscriber
      subscribes_to 'payment.paid'

      def handle(event)
        payment = find_payment(event.payload)
        return if payment.nil?

        result = PallasTrade::FinancialLedger::PostPayment.call(payment: payment)
        return unless result.success?
        return unless result.value[:skipped]

        Rails.logger.info(
          "[FinancialLedger::PaymentPaidSubscriber] skip ledger posting for payment #{payment.prefixed_id}: #{result.value[:reason]}"
        )
      rescue StandardError => e
        Rails.logger.error(
          "[FinancialLedger::PaymentPaidSubscriber] ledger posting failed for payment #{payment&.prefixed_id}: #{e.class} #{e.message}"
        )
      end

      private

      # payment.paid payload 走 PaymentSerializer（含 prefixed id）。双模式：py_ → find_by_param；
      # raw integer（无 prefixed_id 列兼容）→ find_by(id)。
      def find_payment(payload)
        id = payload.try(:[], 'id') || payload.try(:[], :id)
        return if id.blank?

        if id.to_s.start_with?('py_')
          PallasTrade::Payment.find_by_param(id)
        else
          PallasTrade::Payment.find_by(id: id)
        end
      end
    end
  end
end
