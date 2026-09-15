# frozen_string_literal: true

FactoryBot.define do
  factory :back_in_stock_subscription, class: 'PallasTrade::BackInStockSubscription' do
    association :store, factory: [:store]
    association :product
    # nil keeps the legacy product-level subscription; pass a variant for SKU level.
    variant { nil }
    email { 'customer@example.com' }
    status { 'active' }
  end
end
