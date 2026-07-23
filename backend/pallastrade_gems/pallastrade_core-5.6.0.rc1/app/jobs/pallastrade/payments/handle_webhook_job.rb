module PallasTrade
  module Payments
    class HandleWebhookJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.payment_webhooks

      retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
      retry_on ActiveRecord::LockWaitTimeout, wait: 5.seconds, attempts: 3
      discard_on ActiveRecord::RecordNotFound

      def perform(payment_method_id:, action:, payment_session_id:)
        payment_method = PallasTrade::PaymentMethod.find(payment_method_id)
        payment_session = PallasTrade::PaymentSession.find(payment_session_id)

        PallasTrade::Dependencies.payments_handle_webhook_service.constantize.call(
          payment_method: payment_method,
          action: action.to_sym,
          payment_session: payment_session
        )
      end
    end
  end
end
