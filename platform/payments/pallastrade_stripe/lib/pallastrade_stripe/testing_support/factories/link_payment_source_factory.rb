FactoryBot.define do
  factory :link_payment_source, class: PallasTradeStripe::PaymentSources::Link do
    payment_method { create(:stripe_gateway) }
    type { 'PallasTradeStripe::PaymentSources::Link' }
  end
end
