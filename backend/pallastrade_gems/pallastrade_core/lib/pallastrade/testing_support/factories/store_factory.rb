FactoryBot.define do
  factory :store, class: PallasTrade::Store do
    sequence(:code)        { |i| "pallastrade_#{i}" }
    name                   { 'PallasTrade Test Store' }
    url                    { 'www.example.com' }
    mail_from_address      { 'no-reply@example.com' }
    customer_support_email { 'support@example.com' }
    new_order_notifications_email { 'store-owner@example.com' }
    default_currency       { 'USD' }
    supported_currencies   { 'USD,EUR,GBP' }
    default_locale         { 'en' }
    facebook               { 'pallastradecommerce' }
    twitter                { 'pallastradecommerce' }
    instagram              { 'pallastradecommerce' }
    meta_description       { 'Sample store description.' }

  end
end
