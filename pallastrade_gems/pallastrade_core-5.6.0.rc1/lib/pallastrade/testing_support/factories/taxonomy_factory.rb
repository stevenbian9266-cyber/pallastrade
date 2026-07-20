FactoryBot.define do
  factory :taxonomy, class: PallasTrade::Taxonomy do
    sequence(:name) { |n| "taxonomy_#{n}" }
    store { PallasTrade::Store.default }
  end
end
