Rails.application.config.after_initialize do
  Rails.application.config.pallastrade.payment_methods << PallasTradePaypalCheckout::Gateway

end
