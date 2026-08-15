# frozen_string_literal: true

FactoryBot.define do
  factory :redirect, class: 'PallasTrade::Redirect' do
    association :store, factory: [:store]
    from_path { '/old-product' }
    to_path { '/new-product' }
    status_code { 301 }
    active { true }
    title { 'Example redirect' }
    description { 'Old link automatically jumps to the new page.' }
  end
end
