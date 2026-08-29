module PallasTradeStripe
  module WebhookHandlers
    # Legacy-path handler for `checkout.session.async_payment_failed`.
    class CheckoutSessionAsyncPaymentFailed < Base
      def call(event)
        stripe_id = event.data.object.id

        payment_session = PallasTrade::PaymentSessions::Stripe.find_by(external_id: stripe_id)
        return if payment_session.blank?

        payment_session.fail if payment_session.can_fail?
        order = payment_session.order
        order.cancel! if !order.canceled? && order.can_cancel?
      end
    end
  end
end
