FactoryBot.define do
  factory :after_pay_payment_source, class: PallasTradeStripe::PaymentSources::AfterPay do
    payment_method { create(:stripe_gateway) }
    type { 'PallasTradeStripe::PaymentSources::AfterPay' }
  end
end
