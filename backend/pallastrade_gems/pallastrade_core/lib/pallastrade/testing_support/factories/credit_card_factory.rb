FactoryBot.define do
  factory :credit_card, class: PallasTrade::CreditCard do
    verification_value { 123 }
    month              { 12 }
    year               { 1.year.from_now.year }
    number             { '4111111111111111' }
    name               { 'PallasTrade Commerce' }
    cc_type            { 'visa' }

    association(:payment_method, factory: :credit_card_payment_method)
  end
end
