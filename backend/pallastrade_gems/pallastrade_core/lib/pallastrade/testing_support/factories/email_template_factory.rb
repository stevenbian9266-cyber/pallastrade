# frozen_string_literal: true

FactoryBot.define do
  factory :email_template, class: 'PallasTrade::EmailTemplate' do
    association :store, factory: [:store]
    key { 'order.confirm_email' }
    name { 'Order Confirmation' }
    subject { 'Your order {order_number}' }
    body_html { '<h1>Thanks for your order!</h1>' }
    body_text { 'Thanks for your order!' }
    placeholders { 'order_number, store_name' }
    active { true }
  end
end
