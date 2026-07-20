FactoryBot.define do
  factory :customer_group, class: PallasTrade::CustomerGroup do
    sequence(:name) { |n| "Customer Group #{n}" }
    store { PallasTrade::Store.default || create(:store) }
  end
end
