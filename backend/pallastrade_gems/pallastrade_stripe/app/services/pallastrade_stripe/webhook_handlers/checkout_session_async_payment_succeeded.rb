module PallasTradeStripe
  module WebhookHandlers
    # Legacy-path handler for `checkout.session.async_payment_succeeded`
    # (delayed-notification payment methods, e.g. SEPA / bank transfers).
    class CheckoutSessionAsyncPaymentSucceeded < Base
      def call(event)
        enqueue_complete_order_from_session(event.data.object.id)
      end
    end
  end
end
