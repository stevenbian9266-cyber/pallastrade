FactoryBot.define do
  factory :role, class: PallasTrade::Role do
    sequence(:name) { |n| "Role #{n}" }

    factory :admin_role do
      name { 'admin' }
    end
  end
end
