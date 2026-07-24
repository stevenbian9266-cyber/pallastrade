FactoryBot.define do
  factory :option_value, class: PallasTrade::OptionValue do
    sequence(:name) { |n| "Size-#{n}" }
    presentation    { 'S' }
    option_type
  end

  factory :option_value_variant, class: PallasTrade::OptionValueVariant do
    option_value
    variant
  end

  factory :option_type, class: PallasTrade::OptionType do
    sequence(:name) { |n| "foo-size-#{n}" }
    presentation    { 'Size' }

    trait :size do
      name { 'size' }
      presentation { 'Size' }
    end

    trait :color do
      name { 'color' }
      presentation { 'Color' }
      kind { 'color_swatch' }
    end

    trait :color_swatch do
      name { 'color' }
      presentation { 'Color' }
      kind { 'color_swatch' }
    end

    trait :buttons do
      kind { 'buttons' }
    end
  end
end
