# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
FactoryBot.define do
  factory :payment_group, class: PallasTrade::PaymentGroup do
    store { PallasTrade::Store.default || create(:store) }
    customer { create(:user) }
    currency { 'USD' }
    amount { 0 }
    status { 'pending' }

    trait :with_orders do
      after(:create) do |group|
        create_list(:order_with_totals, 2, store: group.store, user: group.customer, payment_group: group)
        group.recalculate!
      end
    end

    trait :processing do
      status { 'processing' }
    end

    trait :completed do
      status { 'completed' }
      completed_at { Time.current }
    end
  end
end
