Rails.application.config.after_initialize do
  Rails.application.config.pallastrade.payment_methods << SpreePaypalCheckout::Gateway

  if Rails.application.config.respond_to?(:PALLASTRADE_storefront)
    Rails.application.config.PALLASTRADE_storefront.head_partials << 'pallastrade_paypal_checkout/head'
  end
end
