FactoryBot.define do
  factory :refresh_token, class: 'PallasTrade::RefreshToken' do
    association :user, factory: :user
    user_type { user.class.to_s }
    expires_at { PallasTrade::RefreshToken.default_expiry.from_now }

    trait :for_admin do
      association :user, factory: :admin_user
    end

    trait :expired do
      expires_at { 1.minute.ago }
    end
  end
end
