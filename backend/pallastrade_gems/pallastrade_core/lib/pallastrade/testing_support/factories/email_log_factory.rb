# frozen_string_literal: true

FactoryBot.define do
  factory :email_log, class: 'PallasTrade::EmailLog' do
    association :store, factory: [:store]
    mailer { 'order' }
    action { 'confirm_email' }
    to { 'customer@example.com' }
    from { 'orders@example.com' }
    subject { 'Order confirmation' }
    status { 'sent' }
    sent_at { Time.current }
  end
end
