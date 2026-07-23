FactoryBot.define do
  factory :przelewy24_payment_source, class: PallasTradeStripe::PaymentSources::Przelewy24 do
    payment_method { create(:stripe_gateway) }
    type { 'PallasTradeStripe::PaymentSources::Przelewy24' }
  end
end
