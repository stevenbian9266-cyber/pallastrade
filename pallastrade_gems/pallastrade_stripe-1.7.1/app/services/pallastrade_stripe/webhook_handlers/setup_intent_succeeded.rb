module PallasTradeStripe
  module WebhookHandlers
    class SetupIntentSucceeded
      def call(event)
        setup_intent_data = event.data.object
        gateway_customer = PallasTrade::GatewayCustomer.find_by(profile_id: setup_intent_data.customer)
        return if gateway_customer.nil?

        pallastrade_payment_method = gateway_customer.payment_method

        user = gateway_customer.user
        return if user.nil?

        begin
          stripe_payment_method = Stripe::PaymentMethod.retrieve(
            setup_intent_data.payment_method,
            { api_key: pallastrade_payment_method.preferred_secret_key }
          )
        rescue Stripe::StripeError => e
          Rails.error.report(e, handled: false, context: { event: event, user_id: user.id }, source: 'pallastrade_stripe')
          return
        end

        PallasTradeStripe::CreateSource.new(
          stripe_payment_method_details: stripe_payment_method,
          stripe_payment_method_id: setup_intent_data.payment_method,
          stripe_billing_details: stripe_payment_method.billing_details,
          gateway: PALLASTRADE_payment_method,
          user: user
        ).call
      end
    end
  end
end
