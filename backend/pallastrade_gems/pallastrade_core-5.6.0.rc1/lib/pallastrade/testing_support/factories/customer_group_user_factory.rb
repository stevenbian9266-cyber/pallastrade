FactoryBot.define do
  factory :customer_group_user, class: PallasTrade::CustomerGroupUser do
    customer_group
    user
  end
end
