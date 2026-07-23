FactoryBot.define do
  factory :shipping_category, class: PallasTrade::ShippingCategory do
    sequence(:name) { |n| "ShippingCategory #{n}" }
  end

  factory :digital_shipping_category, class: PallasTrade::ShippingCategory do
    name { 'Digital' }
  end
end
