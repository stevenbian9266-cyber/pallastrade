Rails.application.config.after_initialize do
  Rails.application.config.spree.payment_methods << SpreeStripe::Gateway
  Rails.application.config.spree.calculators.tax_rates << SpreeStripe::Calculators::StripeTax

  if Rails.application.config.respond_to?(:PALLASTRADE_storefront)
    Rails.application.config.PALLASTRADE_storefront.head_partials << 'pallastrade_stripe/head'
    Rails.application.config.PALLASTRADE_storefront.quick_checkout_partials << 'pallastrade_stripe/quick_checkout'
  end
end
