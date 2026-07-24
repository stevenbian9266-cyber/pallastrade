FactoryBot.define do
  factory :ideal_payment_source, class: PallasTradeStripe::PaymentSources::Ideal do
    payment_method { create(:stripe_gateway) }
    type { 'PallasTradeStripe::PaymentSources::Ideal' }
  end
end
