# frozen_string_literal: true

FactoryBot.define do
  factory :back_in_stock_subscription, class: 'PallasTrade::BackInStockSubscription' do
    association :store, factory: [:store]
    association :product
    email { 'customer@example.com' }
    status { 'active' }
  end
end
