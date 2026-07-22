# Setup Stripe payment method for PallasTrade store
# REPLACE with real Stripe sandbox keys before testing payments
store = PallasTrade::Store.find_by(code: 'pallastrade') || PallasTrade::Store.default

stripe = PallasTrade::PaymentMethod.create_with(
  type: 'PallasTradeStripe::Gateway',
  name: 'Stripe',
  description: 'Pay with credit card via Stripe',
  active: true,
  display_on: 'both',
  auto_capture: true,
  preferred_publishable_key: ENV.fetch('STRIPE_PUBLISHABLE_KEY', 'pk_test_placeholder'),
  preferred_secret_key: ENV.fetch('STRIPE_SECRET_KEY', 'sk_test_placeholder')
).find_or_create_by!(type: 'PallasTradeStripe::Gateway')

stripe.store_ids = [store.id] if stripe.store_ids.empty?
stripe.save! if stripe.changed?
puts "Stripe PM: id=#{stripe.id}, active=#{stripe.active}"
