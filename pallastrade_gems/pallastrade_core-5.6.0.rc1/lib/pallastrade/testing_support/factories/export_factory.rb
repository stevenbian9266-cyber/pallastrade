FactoryBot.define do
  factory :export, class: 'PallasTrade::Export' do
    association :store, factory: :store
    association :user, factory: :admin_user
    type { 'PallasTrade::Exports::Products' }
    format { 'csv' }

    factory :product_export, class: 'PallasTrade::Exports::Products', parent: :export do
      type { 'PallasTrade::Exports::Products' }
    end

    factory :order_export, class: 'PallasTrade::Exports::Orders', parent: :export do
      type { 'PallasTrade::Exports::Orders' }
    end

    factory :customer_export, class: 'PallasTrade::Exports::Customers', parent: :export do
      type { 'PallasTrade::Exports::Customers' }
    end

    factory :coupon_code_export, class: 'PallasTrade::Exports::CouponCodes', parent: :export do
      type { 'PallasTrade::Exports::CouponCodes' }
    end
  end
end
