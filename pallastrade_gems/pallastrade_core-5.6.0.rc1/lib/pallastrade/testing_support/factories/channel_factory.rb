FactoryBot.define do
  factory :channel, class: PallasTrade::Channel do
    store { PallasTrade::Store.default || association(:store) }
    sequence(:name) { |n| "Channel #{n}" }
    sequence(:code) { |n| "channel_#{n}" }
    active { true }
  end
end
