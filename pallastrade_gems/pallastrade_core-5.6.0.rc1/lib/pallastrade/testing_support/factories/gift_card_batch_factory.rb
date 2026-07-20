FactoryBot.define do
  factory :gift_card_batch, class: PallasTrade::GiftCardBatch do
    store { PallasTrade::Store.default || create(:store) }
  end
end
