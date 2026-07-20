# frozen_string_literal: true

FactoryBot.define do
  factory :allowed_origin, class: PallasTrade::AllowedOrigin do
    store
    sequence(:origin) { |n| "https://storefront#{n}.example.com" }
  end
end
