Rails.application.config.after_initialize do
  Rails.application.config.pallastrade.payment_methods << PallasTradePaypalCheckout::Gateway

  if Rails.application.config.respond_to?(:pallastrade_storefront)
    Rails.application.config.pallastrade_storefront.head_partials << 'pallastrade_paypal_checkout/head'
  end
end
