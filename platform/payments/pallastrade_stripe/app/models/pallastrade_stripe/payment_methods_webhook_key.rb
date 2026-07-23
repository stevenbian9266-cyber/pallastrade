module PallasTradeStripe
  class PaymentMethodsWebhookKey < Base
    belongs_to :payment_method, class_name: 'PallasTrade::PaymentMethod'
    belongs_to :webhook_key, class_name: 'PallasTradeStripe::WebhookKey'

    validates :payment_method, presence: true, uniqueness: { scope: :webhook_key_id }
  end
end
