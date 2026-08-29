module PallasTradeStripe
  module WebhookHandlers
    # Legacy-path handler for `checkout.session.completed` — the migration target
    # from `payment_intent.succeeded` (PRD-20260829-payments).
    class CheckoutSessionCompleted < Base
      def call(event)
        enqueue_complete_order_from_session(event.data.object.id)
      end
    end
  end
end
