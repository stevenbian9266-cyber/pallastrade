module PallasTradeStripe
  class CreateWebhookEndpointJob < BaseJob
    def perform(payment_method_id)
      PallasTrade::PaymentMethod.find(payment_method_id).create_webhook_endpoint
    end
  end
end
