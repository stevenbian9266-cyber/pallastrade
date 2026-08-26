# frozen_string_literal: true

FactoryBot.define do
  factory :payment_split, class: PallasTrade::PaymentSplit do
    payment_combination { create(:payment_combination) }
    order { create(:order) }
    payment { create(:payment, order: order) }
    currency { 'USD' }
    authorized_amount { 0 }
    captured_amount { 0 }
    refunded_amount { 0 }
  end
end
