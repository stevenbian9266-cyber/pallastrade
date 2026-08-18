FactoryBot.define do
  factory :review, class: PallasTrade::Review do
    association :store, factory: :store
    association :product, factory: :product
    association :user, factory: :user
    rating { 5 }
    title { 'Great product' }
    body { 'Really happy with this purchase.' }
    status { 'pending' }
    verified_purchase { false }
  end
end
