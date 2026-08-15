# frozen_string_literal: true

FactoryBot.define do
  factory :contact_message, class: 'PallasTrade::ContactMessage' do
    association :store, factory: [:store]
    kind { 'feedback' }
    name { 'Test User' }
    email { 'customer@example.com' }
    subject { 'Feedback' }
    body { 'Great store!' }
    status { 'pending' }
  end
end
