FactoryBot.define do
  factory :product_option_type, class: PallasTrade::ProductOptionType do
    product
    option_type
  end
end
