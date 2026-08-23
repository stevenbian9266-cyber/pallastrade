module PallasTrade
  module Payments
    class HandleWebhook
      prepend PallasTrade::ServiceModule::Base

      # @param payment_method [PallasTrade::PaymentMethod] the payment method that received the webhook
      # @param action [Symbol] normalized action (:captured, :authorized, :failed, :canceled)
      # @param payment_session [PallasTrade::PaymentSession] the payment session associated with the webhook
      # @param metadata [Hash] gateway-specific metadata (e.g. charge data, psp reference)
      def call(payment_method:, action:, payment_session:, metadata: {})
        return success(nil) if payment_session.nil?

        order = payment_session.order

        case action
        when :captured, :authorized
          # PALLAS-CUSTOM: 合并支付组 — 一次成功支付完成组内全部订单（PRD-20260823-checkout-多订单拆分与合并支付）
          if payment_session.payment_group.present?
            handle_group_success(payment_session, metadata)
          else
            handle_success(payment_session, order, metadata)
          end
        when :failed
          payment_session.fail if payment_session.can_fail?
          payment_session.payment_group&.fail if payment_session.payment_group&.can_fail?
          success(payment_session)
        when :canceled
          payment_session.cancel if payment_session.can_cancel?
          payment_session.payment_group&.cancel if payment_session.payment_group&.can_cancel?
          success(payment_session)
        else
          failure(payment_session, "Unknown webhook action: #{action}")
        end
      end

      private

      # PALLAS-CUSTOM: 合并支付组完成（PRD-20260823-checkout-多订单拆分与合并支付）
      # Idempotent — delegates to PallasTrade::PaymentGroups::Complete.
      def handle_group_success(payment_session, metadata)
        payment_session.reload

        if payment_session.completed?
          return success(payment_session)
        end

        payment_group = payment_session.payment_group
        PallasTrade::PaymentGroups::Complete.call(payment_group: payment_group, payment_session: payment_session)
        success(payment_session.reload)
      rescue StandardError => e
        Rails.error.report(e, context: { payment_group_id: payment_session.payment_group&.id, payment_session_id: payment_session.id }, source: 'PallasTrade.payments.webhook.group')
        failure(payment_session, e.message)
      end

      # `PallasTrade::Payment#confirm!` honors the payment method's `auto_capture?` setting:
      # auto_capture → complete! + capture_event; otherwise → pend! (auth-only, payment_state=balance_due).
      def handle_success(payment_session, order, metadata)
        order.with_lock do
          # Idempotency: if the session was already completed (by the API
          # endpoint or a previous webhook), skip duplicate processing.
          if payment_session.reload.completed?
            return success(payment_session)
          end

          payment = payment_session.find_or_create_payment!(metadata)
          payment.confirm! if payment.present? && !payment.completed?
          payment_session.complete if payment_session.can_complete?

          unless order.reload.completed?
            PallasTrade::Dependencies.carts_complete_service.constantize.call(cart: order)
          end
        end

        success(payment_session)
      rescue StandardError => e
        Rails.error.report(e, context: { payment_session_id: payment_session.id, order_id: order.id }, source: 'PallasTrade.payments.webhook')
        failure(payment_session, e.message)
      end
    end
  end
end
