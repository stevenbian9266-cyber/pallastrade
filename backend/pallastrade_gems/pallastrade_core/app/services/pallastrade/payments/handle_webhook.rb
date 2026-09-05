module PallasTrade
  module Payments
    class HandleWebhook
      prepend PallasTrade::ServiceModule::Base

      # @param payment_method [PallasTrade::PaymentMethod] the payment method that received the webhook
      # @param action [Symbol] normalized action (:captured, :authorized, :failed, :canceled)
      # @param payment_session [PallasTrade::PaymentSession] the payment session associated with the webhook
      # @param metadata [Hash] gateway-specific metadata (e.g. charge data, psp reference)
      # payment_method 属于服务契约参数（Job/Controller 统一传参），
      # 业务处理以 payment_session 关联的 order/payment 为准。
      # rubocop:disable Lint/UnusedMethodArgument
      def call(payment_method:, action:, payment_session:, metadata: {})
        # rubocop:enable Lint/UnusedMethodArgument
        return success(nil) if payment_session.nil?

        order = payment_session.order

        case action
        when :captured, :authorized
          handle_success(payment_session, order, metadata)
        when :failed
          payment_session.fail if payment_session.can_fail?
          success(payment_session)
        when :canceled
          payment_session.cancel if payment_session.can_cancel?
          success(payment_session)
        else
          failure(payment_session, "Unknown webhook action: #{action}")
        end
      end

      private

      # `PallasTrade::Payment#confirm!` honors the payment method's `auto_capture?` setting:
      # auto_capture → complete! + capture_event; otherwise → pend! (auth-only, payment_state=balance_due).
      def handle_success(payment_session, order, metadata)
        # P4 (2026-08-27): 组合支付（session 挂 PaymentCombination）走统一组合完成。
        # TXN-P2 (2026-09-05): 收敛到 Transaction Payment Handler——txn 化组合经
        # confirm_payment! + Finalize（组合分支：入账 Settlement + 成员完成，失败→recovery）；
        # legacy 无 txn 组合 → PaymentCombinations::Complete 适配器（Strangler）。
        if payment_session.payment_combination.present?
          result = PallasTrade::Transactions::OnPaymentSuccess.call(payment_session: payment_session.reload)
          return result unless result.success?

          return success(payment_session)
        end

        order.with_lock do
          # Idempotency: if the session was already completed (by the API
          # endpoint or a previous webhook), skip duplicate processing.
          return success(payment_session) if payment_session.reload.completed?

          payment = payment_session.find_or_create_payment!(metadata)
          payment.confirm! if payment.present? && !payment.completed?
          payment_session.complete if payment_session.can_complete?
        end

        # TXN-P2-5 (PRD-20260904-payments-txn-p2-5): 完成收口到 Transaction
        # Payment Handler——带 commerce_transaction 的会话 → confirm_payment! +
        # Transactions::Finalize；legacy 无 txn → 原 Carts::Complete 行为
        # （Strangler）。放在 order 锁外，保持 transaction→order 锁序一致。
        PallasTrade::Transactions::OnPaymentSuccess.call(payment_session: payment_session.reload)

        success(payment_session)
      rescue StandardError => e
        # P0-2 (PRD FR-024): 不再吞掉转 failure —— 未知/transient 异常必须
        # raise，交 Job framework retry（attempt_count +1，event 标记 failed）。
        # 业务确定性失败（订单取消/no_payment_found 等）由服务内分支以 failure
        # 返回，不在此 raise。
        Rails.error.report(e, context: { payment_session_id: payment_session.id, order_id: order.id }, source: 'PallasTrade.payments.webhook')
        raise
      end
    end
  end
end
