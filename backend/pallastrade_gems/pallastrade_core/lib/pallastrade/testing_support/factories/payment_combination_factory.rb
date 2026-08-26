# frozen_string_literal: true

FactoryBot.define do
  factory :payment_combination, class: PallasTrade::PaymentCombination do
    store { create(:store) }
    customer { create(:user) }
    currency { 'USD' }
    amount { 100.0 }
    status { 'pending' }
  end
end
