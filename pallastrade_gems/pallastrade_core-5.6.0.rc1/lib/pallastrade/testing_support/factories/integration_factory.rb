FactoryBot.define do
  factory :integration, class: PallasTrade::Integration do
    type { 'PallasTrade::Integration' }
    store { PallasTrade::Store.default }
    active { true }
  end
end
