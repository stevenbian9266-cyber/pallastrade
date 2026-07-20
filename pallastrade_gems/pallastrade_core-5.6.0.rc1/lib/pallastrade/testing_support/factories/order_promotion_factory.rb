FactoryBot.define do
  factory :order_promotion, class: PallasTrade::OrderPromotion do
    order
    promotion
  end
end
