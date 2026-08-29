module PallasTradeStripe
  class Configuration < PallasTrade::Preferences::Configuration
    preference :supported_webhook_events, :array, default: %w[
      payment_intent.amount_capturable_updated
      payment_intent.payment_failed
      payment_intent.succeeded
      setup_intent.succeeded
      checkout.session.completed
      checkout.session.async_payment_succeeded
      checkout.session.async_payment_failed
      checkout.session.expired
    ]
    preference :use_legacy_webhook_handlers, :boolean, default: false
  end
end
