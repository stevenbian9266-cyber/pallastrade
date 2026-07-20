FactoryBot.define do
  factory :wished_item, class: PallasTrade::WishedItem do
    variant
    wishlist
  end
end
