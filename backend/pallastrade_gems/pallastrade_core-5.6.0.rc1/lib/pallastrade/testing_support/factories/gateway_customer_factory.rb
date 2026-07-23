FactoryBot.define do
  factory :gateway_customer, class: PallasTrade::GatewayCustomer do
    sequence(:profile_id) { |n| "cus_#{n}" }
    user { |p| p.association(:user) }
    payment_method { |p| p.association(:payment_method) }
  end
end
