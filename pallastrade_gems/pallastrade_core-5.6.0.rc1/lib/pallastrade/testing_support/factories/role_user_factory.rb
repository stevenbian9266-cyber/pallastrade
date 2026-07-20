FactoryBot.define do
  factory :role_user, class: 'PallasTrade::RoleUser' do
    association :role, factory: :role
    association :user, factory: :user
    user_type { user.class.to_s }
  end
end
