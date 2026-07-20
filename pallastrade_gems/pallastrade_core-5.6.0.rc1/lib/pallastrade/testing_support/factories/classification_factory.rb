FactoryBot.define do
  factory :classification, class: PallasTrade::Classification do
    product
    taxon

    position { 1 }
  end
end
