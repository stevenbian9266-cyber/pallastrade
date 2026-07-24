FactoryBot.define do
  factory :google_data_feed, class: PallasTrade::DataFeed::Google do
    active         { true }
    association :store, factory: :store
    name           { 'test' }
  end
end
