FactoryBot.define do
  factory :payment_method, class: PallasTrade::PaymentMethod do
    type { 'PallasTrade::PaymentMethod' }
    name { 'Test' }
    store { PallasTrade::Store.find_by(default: true) || association(:store) }
  end

  factory :check_payment_method, parent: :payment_method, class: PallasTrade::PaymentMethod::Check do
    type { 'PallasTrade::PaymentMethod::Check' }
    name { 'Check' }
  end

  factory :credit_card_payment_method, parent: :payment_method, class: PallasTrade::Gateway::Bogus do
    type { 'PallasTrade::Gateway::Bogus' }
    name { 'Credit Card' }
  end

  factory :simple_credit_card_payment_method, parent: :credit_card_payment_method

  factory :store_credit_payment_method, parent: :payment_method, class: PallasTrade::PaymentMethod::StoreCredit do
    type          { 'PallasTrade::PaymentMethod::StoreCredit' }
    name          { 'Store Credit' }
    description   { 'Store Credit' }
    active        { true }
    auto_capture  { true }
  end

  factory :custom_payment_method, parent: :payment_method, class: PallasTrade::Gateway::CustomPaymentSourceMethod do
    type { 'PallasTrade::Gateway::CustomPaymentSourceMethod' }
    name { 'Custom' }
  end

  factory :bogus_payment_method, parent: :credit_card_payment_method
end
