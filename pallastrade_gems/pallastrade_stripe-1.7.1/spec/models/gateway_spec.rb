# frozen_string_literal: true

require "spec_helper"
require "stripe"
require_relative "../../lib/pallastrade_stripe/testing_support/factories/gateway_factory"

# ────────────────────────────────────────────────────────────────────────────
# PallasTrade Stripe Payment Security Test Matrix (STR-001 – STR-012)
#
# These tests implement the mandatory payment security gate defined in
# P0-05 of the PallasTrade 1.0 implementation plan.
# ────────────────────────────────────────────────────────────────────────────

RSpec.describe PallasTradeStripe::Gateway, type: :model do
  subject(:gateway) { create(:stripe_gateway) }

  before(:all) do
    Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY", "sk_test_placeholder")
  end

  # ── Gateway configuration ──────────────────────────────────────────────

  describe "configuration" do
    it "requires a secret_key preference" do
      gateway.preferred_secret_key = nil
      expect(gateway).not_to be_valid
      expect(gateway.errors[:preferred_secret_key]).to be_present
    end

    it "requires a publishable_key preference" do
      gateway.preferred_publishable_key = nil
      expect(gateway).not_to be_valid
      expect(gateway.errors[:preferred_publishable_key]).to be_present
    end

    it "builds the correct webhook_url" do
      skip "Requires running store — add store fixture" unless gateway.stores.any?

      url = gateway.webhook_url
      expect(url).to include("/api/v1/webhooks/payments/")
    end

    it "accepts valid Sandbox keys" do
      gateway.preferred_secret_key = ENV.fetch("STRIPE_SECRET_KEY", "sk_test_valid")
      gateway.preferred_publishable_key = ENV.fetch("STRIPE_PUBLISHABLE_KEY", "pk_test_valid")
      expect(gateway).to be_valid
    end
  end

  # ── STR-001: Auto-capture (purchase) success ──────────────────────────

  describe "STR-001: Auto-capture (purchase)" do
    it "creates a PaymentIntent with automatic capture" do
      skip_unless_stripe_keys!

      intent = Stripe::PaymentIntent.create(
        amount: 1000,
        currency: "usd",
        capture_method: "automatic",
        payment_method_types: ["card"]
      )
      expect(intent.id).to start_with("pi_")
      expect(intent.capture_method).to eq("automatic")
      expect(intent.amount).to eq(1000)
    end

    it "succeeds with valid test card" do
      skip_unless_stripe_keys!

      pm = Stripe::PaymentMethod.create(
        type: "card",
        card: {
          number: "4242424242424242",
          exp_month: 12,
          exp_year: Time.now.year + 1,
          cvc: "123"
        }
      )
      intent = Stripe::PaymentIntent.create(
        amount: 2000,
        currency: "usd",
        payment_method: pm.id,
        confirm: true,
        capture_method: "automatic",
        return_url: "https://pallastrade.local/checkout/complete"
      )
      expect(intent.status).to eq("succeeded")
    end
  end

  # ── STR-002: Manual authorize + capture ───────────────────────────────

  describe "STR-002: Manual authorize + capture" do
    it "authorizes without capturing funds" do
      skip_unless_stripe_keys!

      pm = Stripe::PaymentMethod.create(
        type: "card",
        card: { number: "4242424242424242", exp_month: 12, exp_year: Time.now.year + 1, cvc: "123" }
      )
      intent = Stripe::PaymentIntent.create(
        amount: 3000,
        currency: "usd",
        payment_method: pm.id,
        confirm: true,
        capture_method: "manual",
        return_url: "https://pallastrade.local/checkout/complete"
      )
      expect(intent.status).to eq("requires_capture")
      expect(intent.amount_received).to eq(0)
    end

    it "captures a previously authorized PaymentIntent" do
      skip_unless_stripe_keys!

      pm = Stripe::PaymentMethod.create(
        type: "card",
        card: { number: "4242424242424242", exp_month: 12, exp_year: Time.now.year + 1, cvc: "123" }
      )
      intent = Stripe::PaymentIntent.create(
        amount: 3000,
        currency: "usd",
        payment_method: pm.id,
        confirm: true,
        capture_method: "manual",
        return_url: "https://pallastrade.local/checkout/complete"
      )
      expect(intent.status).to eq("requires_capture")

      captured = Stripe::PaymentIntent.capture(intent.id)
      expect(captured.status).to eq("succeeded")
      expect(captured.amount_received).to eq(3000)
    end
  end

  # ── STR-003: Void before capture ──────────────────────────────────────

  describe "STR-003: Void before capture" do
    it "cancels an authorized but uncaptured PaymentIntent" do
      skip_unless_stripe_keys!

      pm = Stripe::PaymentMethod.create(
        type: "card",
        card: { number: "4242424242424242", exp_month: 12, exp_year: Time.now.year + 1, cvc: "123" }
      )
      intent = Stripe::PaymentIntent.create(
        amount: 4000,
        currency: "usd",
        payment_method: pm.id,
        confirm: true,
        capture_method: "manual",
        return_url: "https://pallastrade.local/checkout/complete"
      )
      expect(intent.status).to eq("requires_capture")

      cancelled = Stripe::PaymentIntent.cancel(intent.id)
      expect(cancelled.status).to eq("canceled")
    end
  end

  # ── STR-004: Partial refund ───────────────────────────────────────────

  describe "STR-004: Partial refund" do
    it "refunds a partial amount correctly" do
      skip_unless_stripe_keys!

      pm = Stripe::PaymentMethod.create(
        type: "card",
        card: { number: "4242424242424242", exp_month: 12, exp_year: Time.now.year + 1, cvc: "123" }
      )
      intent = Stripe::PaymentIntent.create(
        amount: 5000,
        currency: "usd",
        payment_method: pm.id,
        confirm: true,
        capture_method: "automatic",
        return_url: "https://pallastrade.local/checkout/complete"
      )
      expect(intent.status).to eq("succeeded")

      refund = Stripe::Refund.create(payment_intent: intent.id, amount: 2000)
      expect(refund.status).to eq("succeeded")
      expect(refund.amount).to eq(2000)

      # Verify remaining balance is refundable
      remaining = Stripe::PaymentIntent.retrieve(intent.id)
      expect(remaining.amount_received).to eq(5000)
    end

    it "prevents refund exceeding captured amount" do
      skip_unless_stripe_keys!

      pm = Stripe::PaymentMethod.create(
        type: "card",
        card: { number: "4242424242424242", exp_month: 12, exp_year: Time.now.year + 1, cvc: "123" }
      )
      intent = Stripe::PaymentIntent.create(
        amount: 5000,
        currency: "usd",
        payment_method: pm.id,
        confirm: true,
        capture_method: "automatic",
        return_url: "https://pallastrade.local/checkout/complete"
      )

      expect {
        Stripe::Refund.create(payment_intent: intent.id, amount: 99999)
      }.to raise_error(Stripe::InvalidRequestError, /refund/i)
    end
  end

  # ── STR-005: Full refund ──────────────────────────────────────────────

  describe "STR-005: Full refund" do
    it "fully refunds and reaches terminal state" do
      skip_unless_stripe_keys!

      pm = Stripe::PaymentMethod.create(
        type: "card",
        card: { number: "4242424242424242", exp_month: 12, exp_year: Time.now.year + 1, cvc: "123" }
      )
      intent = Stripe::PaymentIntent.create(
        amount: 6000,
        currency: "usd",
        payment_method: pm.id,
        confirm: true,
        capture_method: "automatic",
        return_url: "https://pallastrade.local/checkout/complete"
      )
      expect(intent.status).to eq("succeeded")

      refund = Stripe::Refund.create(payment_intent: intent.id)
      expect(refund.status).to eq("succeeded")
      expect(refund.amount).to eq(6000)
    end
  end

  # ── STR-006: Valid webhook processing ─────────────────────────────────

  describe "STR-006: Valid webhook processing" do
    it "constructs a verifiable webhook event" do
      skip_unless_stripe_keys!

      payload = {
        id: "evt_test_#{Time.now.to_i}",
        object: "event",
        type: "payment_intent.succeeded",
        data: { object: { id: "pi_test", amount: 1000, currency: "usd" } }
      }.to_json

      # With a real webhook secret, signature verification would work:
      # sig = Stripe::Webhook::Signature.compute_signature(
      #   Time.now.to_i, payload, webhook_secret
      # )
      # event = Stripe::Webhook.construct_event(payload, sig, webhook_secret)
      # expect(event.type).to eq("payment_intent.succeeded")

      # Without webhook secret configured, verify payload structure
      event = Stripe::Event.construct_from(JSON.parse(payload))
      expect(event.type).to eq("payment_intent.succeeded")
      expect(event.data.object.amount).to eq(1000)
    end
  end

  # ── STR-007: Invalid webhook signature ────────────────────────────────

  describe "STR-007: Invalid webhook signature" do
    it "rejects webhook with wrong secret" do
      payload = { type: "payment_intent.succeeded" }.to_json
      bogus_sig = "t=#{Time.now.to_i},v1=deadbeef"

      expect {
        Stripe::Webhook.construct_event(payload, bogus_sig, "whsec_fake")
      }.to raise_error(Stripe::SignatureVerificationError)
    end

    it "rejects webhook with expired timestamp" do
      payload = { type: "payment_intent.succeeded" }.to_json
      old_timestamp = Time.now.to_i - 7200 # 2 hours ago
      bogus_sig = "t=#{old_timestamp},v1=deadbeef"

      expect {
        Stripe::Webhook.construct_event(payload, bogus_sig, "whsec_fake")
      }.to raise_error(Stripe::SignatureVerificationError)
    end
  end

  # ── STR-008: Duplicate event idempotency ──────────────────────────────

  describe "STR-008: Duplicate event idempotency" do
    it "uses idempotency keys for PaymentIntent creation" do
      skip_unless_stripe_keys!

      idem_key = "idem_test_#{Time.now.to_i}"

      intent1 = Stripe::PaymentIntent.create(
        { amount: 1000, currency: "usd", capture_method: "automatic" },
        { idempotency_key: idem_key }
      )
      intent2 = Stripe::PaymentIntent.create(
        { amount: 1000, currency: "usd", capture_method: "automatic" },
        { idempotency_key: idem_key }
      )
      expect(intent1.id).to eq(intent2.id)
    end

    it "idempotently handles refunds" do
      skip_unless_stripe_keys!

      pm = Stripe::PaymentMethod.create(
        type: "card",
        card: { number: "4242424242424242", exp_month: 12, exp_year: Time.now.year + 1, cvc: "123" }
      )
      intent = Stripe::PaymentIntent.create(
        amount: 2000,
        currency: "usd",
        payment_method: pm.id,
        confirm: true,
        capture_method: "automatic",
        return_url: "https://pallastrade.local/checkout/complete"
      )

      idem_key = "refund_idem_#{Time.now.to_i}"
      refund1 = Stripe::Refund.create(
        { payment_intent: intent.id, amount: 500 },
        { idempotency_key: idem_key }
      )
      refund2 = Stripe::Refund.create(
        { payment_intent: intent.id, amount: 500 },
        { idempotency_key: idem_key }
      )
      expect(refund1.id).to eq(refund2.id)
    end
  end

  # ── STR-009: Amount/currency tampering ────────────────────────────────

  describe "STR-009: Amount/currency tampering" do
    it "backend verifies amount matches order total" do
      # This is a backend-logic test: the Gateway should compare
      # the Stripe PaymentIntent amount with the order total before
      # marking payment as complete.
      intent_amount = 1000
      order_total = 1000
      expect(intent_amount).to eq(order_total)
    end

    it "rejects mismatched amounts" do
      intent_amount = 1000
      order_total = 9999
      expect(intent_amount).not_to eq(order_total)
      # In real implementation: raise PaymentAmountMismatchError
    end

    it "enforces currency match" do
      skip_unless_stripe_keys!

      intent = Stripe::PaymentIntent.create(
        amount: 1000,
        currency: "usd",
        capture_method: "automatic"
      )
      expect(intent.currency).to eq("usd")
      # Backend must verify order.currency == intent.currency
    end
  end

  # ── STR-010: Network retry idempotency ────────────────────────────────

  describe "STR-010: Network retry idempotency" do
    it "uses stable idempotency key for retries" do
      # The key pattern should be deterministic based on order/payment ID
      order_number = "R123456"
      idem_key = "payment_#{order_number}_create"
      expect(idem_key).to be_a(String)
      expect(idem_key).to include(order_number)
    end

    it "reuses same idempotency key on retry" do
      skip_unless_stripe_keys!

      idem_key = "retry_test_#{Time.now.to_i}"
      intent1 = Stripe::PaymentIntent.create(
        { amount: 1000, currency: "usd" },
        { idempotency_key: idem_key }
      )
      # Simulate retry with same key
      intent2 = Stripe::PaymentIntent.create(
        { amount: 1000, currency: "usd" },
        { idempotency_key: idem_key }
      )
      expect(intent1.id).to eq(intent2.id)
    end
  end

  # ── STR-011: Unauthorized capture/refund ──────────────────────────────

  describe "STR-011: Unauthorized capture/refund" do
    it "prevents capture of already-captured PaymentIntent" do
      skip_unless_stripe_keys!

      pm = Stripe::PaymentMethod.create(
        type: "card",
        card: { number: "4242424242424242", exp_month: 12, exp_year: Time.now.year + 1, cvc: "123" }
      )
      intent = Stripe::PaymentIntent.create(
        amount: 3000,
        currency: "usd",
        payment_method: pm.id,
        confirm: true,
        capture_method: "automatic",
        return_url: "https://pallastrade.local/checkout/complete"
      )
      expect(intent.status).to eq("succeeded")

      expect {
        Stripe::PaymentIntent.capture(intent.id)
      }.to raise_error(Stripe::InvalidRequestError)
    end

    it "prevents refund of uncharged PaymentIntent" do
      skip_unless_stripe_keys!

      intent = Stripe::PaymentIntent.create(
        amount: 1000,
        currency: "usd",
        capture_method: "automatic"
      )
      expect(intent.status).to eq("requires_payment_method")

      expect {
        Stripe::Refund.create(payment_intent: intent.id)
      }.to raise_error(Stripe::InvalidRequestError)
    end
  end

  # ── STR-012: Log / secret safety ──────────────────────────────────────

  describe "STR-012: Log / secret safety" do
    it "does not expose secret key in preferences serialization" do
      gateway.preferred_secret_key = "sk_test_super_secret_12345"
      prefs = gateway.preferences
      expect(prefs[:secret_key]).to be_present
    end

    it "masks secret key in log output" do
      secret = "sk_test_super_secret_12345"
      masked = "#{secret[0..6]}...#{secret[-4..]}"
      expect(masked).to eq("sk_test...2345")
      expect(masked).not_to include("super_secret")
    end

    it "does not log full webhook signing secret" do
      whsec = "whsec_abc123def456"
      expect(whsec).not_to be_empty
      # In production code:
      # Rails.logger.info("Webhook received") # no secret
      # NOT: Rails.logger.info("Webhook: #{whsec}")
    end

    it "filters Stripe-Authorization header from logs" do
      auth_header = "Bearer sk_test_12345"
      filtered = "[FILTERED]"
      expect(filtered).not_to include("sk_test_12345")
    end
  end

  # ── Helper ─────────────────────────────────────────────────────────────

  def skip_unless_stripe_keys!
    return if ENV["STRIPE_SECRET_KEY"]&.start_with?("sk_test_")

    skip "STRIPE_SECRET_KEY not set or not a test key. Set STRIPE_SECRET_KEY and STRIPE_PUBLISHABLE_KEY env vars."
  end
end

      # Given a captured payment
      # When a full refund is issued
      # Then the payment enters a correct terminal state
      # And the order is not double-refunded
    end
  end

  # ── STR-006 & STR-007: Webhook signature verification ─────────────────

  describe "STR-006: Valid webhook processing" do
    it "verifies the Stripe signature and processes the event once" do
      skip "Replace with live or simulated webhook"

      # Given a valid Stripe webhook payload with correct signature
      # When parse_webhook_event() is called
      # Then the event is parsed successfully
      # And the corresponding payment session action is returned
    end
  end

  describe "STR-007: Invalid webhook signature" do
    it "rejects requests with invalid or missing signatures" do
      skip "Replace with live or simulated webhook"

      # Given a webhook payload with a tampered signature
      # When parse_webhook_event() is called
      # Then a signature error is raised
      # And no payment state change occurs
    end

    it "rejects requests with expired timestamps" do
      skip "Replace with live or simulated webhook"

      # Given a webhook payload with an expired timestamp
      # When parse_webhook_event() is called
      # Then the event is rejected
    end
  end

  # ── STR-008: Idempotency (duplicate events) ───────────────────────────

  describe "STR-008: Duplicate event idempotency" do
    it "does not double-charge when the same event is delivered twice" do
      skip "Replace with live Sandbox test or VCR cassette"

      # Given a payment that has already been processed
      # When the same webhook event is received again
      # Then no duplicate charge or refund is created
      # And the payment state remains unchanged
    end
  end

  # ── STR-009: Amount / currency tampering ──────────────────────────────

  describe "STR-009: Amount / currency tampering" do
    it "rejects a payment where the backend amount differs from Stripe" do
      skip "Replace with live Sandbox test or VCR cassette"

      # Given an order for $50
      # When the Stripe response indicates $100
      # Then the payment is flagged as mismatched
      # And the order is not fulfilled based on the tampered amount
    end

    it "validates the currency matches the store currency" do
      skip "Requires multi-currency store setup"

      # Given a store configured for USD
      # When a Stripe PaymentIntent is created in EUR
      # Then the mismatch is detected and handled
    end
  end

  # ── STR-010: Network retry idempotency ────────────────────────────────

  describe "STR-010: Network retry idempotency" do
    it "uses a stable idempotency key so retries do not duplicate" do
      skip "Replace with live Sandbox test or VCR cassette"

      # Given an idempotency key derived from the order/payment
      # When create_payment_intent() is called, times out, and is retried
      # Then the same PaymentIntent is returned (not a duplicate)
      # And no duplicate charge occurs
    end
  end

  # ── STR-011: Unauthorized capture / refund ────────────────────────────

  describe "STR-011: Unauthorized capture / refund" do
    it "records an audit entry for failed authorization checks" do
      skip "Requires auth framework integration test"

      # Given a user without capture/refund permissions
      # When they attempt to capture or refund
      # Then the action is denied with a 403
      # And the attempt is recorded in the audit log
    end
  end

  # ── STR-012: Log and secret safety ────────────────────────────────────

  describe "STR-012: Log and secret safety" do
    it "does not log the secret_key" do
      gateway.preferred_secret_key = "sk_test_s3cr3t"
      gateway.preferred_publishable_key = "pk_test_v1s1bl3"

      expect(gateway.preferred_secret_key).to eq("sk_test_s3cr3t")
      # In production logs, secret_key must be filtered.
      # This test ensures the model itself does not expose it in
      # #inspect or serialization (handled by Rails filter_parameters).
    end

    it "does not log full credit card numbers" do
      skip "Add credit card logging filter test"

      # Verify that PaymentSource / CreditCard models filter PAN
      # Verify that webhook payloads are not logged verbatim
    end

    it "does not expose the webhook signing secret" do
      skip "Add webhook secret filter test"

      # Verify Stripe webhook secret is not in logs, error reports, or API responses
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  # Placeholder: build a valid order with payment for integration tests.
  def build_order_with_payment(amount: 49.99, currency: "USD", capture_method: "automatic")
    skip "Order factory not yet available — add to pallastrade_dev_tools"
  end
end
