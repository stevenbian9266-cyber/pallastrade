FactoryBot.define do
  factory :sepa_debit_payment_source, class: PallasTradeStripe::PaymentSources::SepaDebit do
    payment_method { create(:stripe_gateway) }
    type { 'PallasTradeStripe::PaymentSources::SepaDebit' }
  end
end
