FactoryBot.define do
  factory :policy, class: 'PallasTrade::Policy' do
    owner { PallasTrade::Store.default }
    slug { 'my-policy' }
    name { 'My Policy' }
    body { 'This is the my policy' }
  end
end
