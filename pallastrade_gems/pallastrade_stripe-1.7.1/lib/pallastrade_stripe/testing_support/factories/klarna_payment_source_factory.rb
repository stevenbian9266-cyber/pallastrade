FactoryBot.define do
  factory :klarna_payment_source, class: PallasTradeStripe::PaymentSources::Klarna do
    payment_method { create(:stripe_gateway) }
    type { 'PallasTradeStripe::PaymentSources::Klarna' }
  end
end
