module PallasTradeStripe
  module WebhookHandlers
    class Base
      # Delay before processing a webhook to give the storefront's own session-complete
      # request a chance to land first, avoiding double-processing of the same payment.
      ENQUEUE_DELAY = 10.seconds

      private

      def enqueue_complete_order_from_session(stripe_id)
        payment_session = resolve_payment_session(stripe_id)
        return nil if payment_session.nil?

        PallasTradeStripe::CompleteOrderFromSessionJob.set(wait: ENQUEUE_DELAY).perform_later(payment_session.id)
        payment_session
      end

      # PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): sessions now store the
      # `cs_` Checkout Session id. `payment_intent.*` events carry a `pi_` id, so
      # resolve the owning Checkout Session via the Stripe API when needed.
      #
      # PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
      # PaymentIntent 模式（自绘卡字段）external_id 直存 `pi_` id → 先直查命中，
      # 未命中再反查 Checkout Session。
      def resolve_payment_session(stripe_id)
        return PallasTrade::PaymentSessions::Stripe.find_by(external_id: stripe_id) if stripe_id.to_s.start_with?('cs_')

        direct = PallasTrade::PaymentSessions::Stripe.find_by(external_id: stripe_id)
        return direct if direct.present?

        gateway = PallasTrade::PaymentMethod.of_type('PallasTradeStripe::Gateway').first
        return nil unless gateway

        session = Stripe::Checkout::Session.list(
          { payment_intent: stripe_id, limit: 1 },
          { api_key: gateway.preferred_secret_key }
        ).first
        session && PallasTrade::PaymentSessions::Stripe.find_by(external_id: session.id)
      rescue Stripe::StripeError
        nil
      end
    end
  end
end
