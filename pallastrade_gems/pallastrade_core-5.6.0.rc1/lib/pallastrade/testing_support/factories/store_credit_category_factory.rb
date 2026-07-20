FactoryBot.define do
  factory :store_credit_category, class: PallasTrade::StoreCreditCategory do
    name { 'Exchange' }
  end

  factory :store_credit_gift_card_category, class: PallasTrade::StoreCreditCategory do
    name { PallasTrade::StoreCreditCategory::GIFT_CARD_CATEGORY_NAME }
  end
end
