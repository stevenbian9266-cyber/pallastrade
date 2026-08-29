# for local setup you need to use Stripe-CLI and change the key manually
StripeEvent.signing_secret = ENV['STRIPE_SIGNING_SECRET'] if ENV['STRIPE_SIGNING_SECRET'].present?

Stripe.log_level = ENV.fetch('STRIPE_LOG_LEVEL', 'debug')
Stripe.api_version = '2023-10-16'
Stripe.set_app_info('PallasTrade Stripe', version: PallasTrade.version, url: 'https://pallastrade.cn')

Rails.application.config.after_initialize do
  StripeEvent.configure do |events|
    events.subscribe 'payment_intent.succeeded', PallasTradeStripe::WebhookHandlers::PaymentIntentSucceeded.new
    events.subscribe 'payment_intent.amount_capturable_updated', PallasTradeStripe::WebhookHandlers::PaymentIntentAmountCapturableUpdated.new
    events.subscribe 'payment_intent.payment_failed', PallasTradeStripe::WebhookHandlers::PaymentIntentPaymentFailed.new
    events.subscribe 'setup_intent.succeeded', PallasTradeStripe::WebhookHandlers::SetupIntentSucceeded.new
    # PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): Checkout Session events.
    events.subscribe 'checkout.session.completed', PallasTradeStripe::WebhookHandlers::CheckoutSessionCompleted.new
    events.subscribe 'checkout.session.async_payment_succeeded', PallasTradeStripe::WebhookHandlers::CheckoutSessionAsyncPaymentSucceeded.new
    events.subscribe 'checkout.session.async_payment_failed', PallasTradeStripe::WebhookHandlers::CheckoutSessionAsyncPaymentFailed.new
    events.subscribe 'checkout.session.expired', PallasTradeStripe::WebhookHandlers::CheckoutSessionExpired.new
  end
end
