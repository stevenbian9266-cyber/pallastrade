module PallasTradeStripe
  module WebhookHandlers
    # Legacy-path handler for `checkout.session.expired` (24h TTL).
    class CheckoutSessionExpired < Base
      def call(event)
        stripe_id = event.data.object.id

        payment_session = PallasTrade::PaymentSessions::Stripe.find_by(external_id: stripe_id)
        return if payment_session.blank?

        payment_session.cancel if payment_session.can_cancel?
        order = payment_session.order
        order.cancel! if !order.canceled? && order.can_cancel?
      end
    end
  end
end
