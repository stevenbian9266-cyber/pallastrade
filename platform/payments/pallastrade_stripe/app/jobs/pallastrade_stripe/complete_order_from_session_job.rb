module PallasTradeStripe
  class CompleteOrderFromSessionJob < BaseJob
    def perform(payment_session_id)
      payment_session = PallasTrade::PaymentSessions::Stripe.find(payment_session_id)

      # PaymentSessions::Stripe duck-types as PaymentIntent
      PallasTradeStripe::CompleteOrder.new(payment_intent: payment_session).call

      payment_session.complete if payment_session.can_complete?
    end
  end
end
