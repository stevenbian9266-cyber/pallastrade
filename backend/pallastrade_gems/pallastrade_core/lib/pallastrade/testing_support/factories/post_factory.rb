# frozen_string_literal: true

FactoryBot.define do
  factory :post, class: 'PallasTrade::Post' do
    association :store, factory: [:store]
    title { 'Welcome to our store' }
    slug { 'welcome-to-our-store' }
    excerpt { 'A short introduction to our brand.' }
    author { 'PallasTrade Team' }
    published_at { Time.current }

    trait :draft do
      published_at { nil }
    end

    trait :scheduled do
      published_at { 1.day.from_now }
    end

    trait :unpublished do
      published_at { 1.day.ago }
    end
  end
end
