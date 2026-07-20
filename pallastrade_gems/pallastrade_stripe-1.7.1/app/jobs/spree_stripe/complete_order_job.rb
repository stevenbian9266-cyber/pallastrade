module PallasTradeStripe
  class CompleteOrderJob < BaseJob
    def perform(payment_intent_id)
      payment_intent = PallasTradeStripe::PaymentIntent.find(payment_intent_id)
      PallasTradeStripe::CompleteOrder.new(payment_intent: payment_intent).call
    end
  end
end
