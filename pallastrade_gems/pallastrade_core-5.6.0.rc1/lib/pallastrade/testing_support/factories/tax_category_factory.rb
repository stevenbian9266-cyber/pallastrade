FactoryBot.define do
  factory :tax_category, class: PallasTrade::TaxCategory do
    name { "TaxCategory - #{rand(999_999)}" }
    description { generate(:random_string) }
  end
end
