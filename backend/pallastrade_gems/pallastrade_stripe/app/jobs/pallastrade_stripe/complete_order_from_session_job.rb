module PallasTradeStripe
  class CompleteOrderFromSessionJob < BaseJob
    def perform(payment_session_id)
      payment_session = PallasTrade::PaymentSessions::Stripe.find(payment_session_id)

      # PALLAS-CUSTOM: 合并支付 �?支付组会话完成组内全部订单（PRD-20260823-checkout-多订单拆分与合并支付�?
      if payment_session.payment_group.present?
        PallasTradeStripe::CompletePaymentGroup.new(payment_session: payment_session).call
      else
        # PaymentSessions::Stripe duck-types as PaymentIntent
        PallasTradeStripe::CompleteOrder.new(payment_intent: payment_session).call
      end

      payment_session.complete if payment_session.can_complete?
    end
  end
end
