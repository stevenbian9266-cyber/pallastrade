FactoryBot.define do
  factory :alipay_payment_source, class: PallasTradeStripe::PaymentSources::Alipay do
    payment_method { create(:stripe_gateway) }
    type { 'PallasTradeStripe::PaymentSources::Alipay' }
  end
end
