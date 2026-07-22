# frozen_string_literal: true

# Stripe Sandbox test helper — loaded by spec_helper or rails_helper
# Requires STRIPE_SECRET_KEY and STRIPE_PUBLISHABLE_KEY env vars.
# See: PallasTrade 1.0 Payment Security Gate (STR-001–STR-012)

require "stripe"

module PallasTradeStripeTestHelpers
  SANDBOX_CARD_VISA   = "4242424242424242"
  SANDBOX_CARD_MASTER = "5555555555554444"
  SANDBOX_CARD_DECLINED = "4000000000000002"

  def self.configure!
    Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY", nil)
    Stripe.api_version = "2025-03-01"
  end

  def self.enabled?
    !Stripe.api_key.nil? && Stripe.api_key.start_with?("sk_test_")
  end

  def self.skip_unless_enabled!(example)
    return if enabled?

    skip "Stripe Sandbox keys not configured. Set STRIPE_SECRET_KEY and STRIPE_PUBLISHABLE_KEY env vars."
  end

  # Create a minimal PaymentIntent in Stripe Sandbox for test use
  def self.create_test_payment_intent(amount: 1000, currency: "usd", capture_method: "automatic")
    Stripe::PaymentIntent.create(
      amount: amount,
      currency: currency,
      capture_method: capture_method,
      payment_method_types: ["card"]
    )
  end
end

# Auto-configure when loaded
PallasTradeStripeTestHelpers.configure!
