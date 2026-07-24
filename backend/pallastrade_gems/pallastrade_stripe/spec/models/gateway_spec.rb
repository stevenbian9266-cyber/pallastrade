# frozen_string_literal: true

require "spec_helper"
require "stripe"
require "openssl"
require "securerandom"

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
      expect(url).to include("/api/v3/webhooks/payments/")
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

      intent = Stripe::PaymentIntent.create(
        amount: 2000,
        currency: "usd",
        payment_method: "pm_card_visa",
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

      intent = Stripe::PaymentIntent.create(
        amount: 3000,
        currency: "usd",
        payment_method: "pm_card_visa",
        confirm: true,
        capture_method: "manual",
        return_url: "https://pallastrade.local/checkout/complete"
      )
      expect(intent.status).to eq("requires_capture")
      expect(intent.amount_received).to eq(0)
    end

    it "captures a previously authorized PaymentIntent" do
      skip_unless_stripe_keys!

      intent = Stripe::PaymentIntent.create(
        amount: 3000,
        currency: "usd",
        payment_method: "pm_card_visa",
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

      intent = Stripe::PaymentIntent.create(
        amount: 4000,
        currency: "usd",
        payment_method: "pm_card_visa",
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

      intent = Stripe::PaymentIntent.create(
        amount: 5000,
        currency: "usd",
        payment_method: "pm_card_visa",
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

      intent = Stripe::PaymentIntent.create(
        amount: 5000,
        currency: "usd",
        payment_method: "pm_card_visa",
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

      intent = Stripe::PaymentIntent.create(
        amount: 6000,
        currency: "usd",
        payment_method: "pm_card_visa",
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
    it "verifies a correctly signed payload with the gateway signing secret" do
      secret = "whsec_valid_test_secret"
      attach_webhook_secret(gateway, secret)
      payload = {
        id: "evt_valid_signature",
        object: "event",
        type: "payment_intent.succeeded",
        data: { object: { id: "pi_test", amount: 1000, currency: "usd" } }
      }.to_json
      headers = { "HTTP_STRIPE_SIGNATURE" => stripe_signature_header(payload, secret) }

      event = gateway.send(:verify_webhook_signature, payload, headers)

      expect(event.id).to eq("evt_valid_signature")
      expect(event.type).to eq("payment_intent.succeeded")
      expect(event.data.object.amount).to eq(1000)
    end
  end

  # ── STR-007: Invalid webhook signature ────────────────────────────────

  describe "STR-007: Invalid webhook signature" do
    let(:webhook_secret) { "whsec_expected_test_secret" }
    let(:payload) { { type: "payment_intent.succeeded" }.to_json }

    before do
      attach_webhook_secret(gateway, webhook_secret)
    end

    it "rejects a payload signed with the wrong secret" do
      headers = { "HTTP_STRIPE_SIGNATURE" => stripe_signature_header(payload, "whsec_wrong") }

      expect {
        gateway.send(:verify_webhook_signature, payload, headers)
      }.to raise_error(PallasTrade::PaymentMethod::WebhookSignatureError, "Invalid webhook signature")
    end

    it "rejects an otherwise valid signature with an expired timestamp" do
      expired_at = Time.now.to_i - 7200
      headers = {
        "HTTP_STRIPE_SIGNATURE" => stripe_signature_header(payload, webhook_secret, timestamp: expired_at)
      }

      expect {
        gateway.send(:verify_webhook_signature, payload, headers)
      }.to raise_error(PallasTrade::PaymentMethod::WebhookSignatureError, "Invalid webhook signature")
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

      intent = Stripe::PaymentIntent.create(
        amount: 2000,
        currency: "usd",
        payment_method: "pm_card_visa",
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
    def payment_intent(amount:, currency:)
      Stripe::PaymentIntent.construct_from(
        id: "pi_amount_check",
        amount: amount,
        currency: currency,
        status: "succeeded"
      )
    end

    it "accepts the provider response only when amount and currency match" do
      intent = payment_intent(amount: 1000, currency: "usd")

      expect(gateway.send(:verify_payment_intent_matches!, intent, 1000, "USD")).to be(true)
    end

    it "rejects a provider amount that differs from the server-side payment" do
      intent = payment_intent(amount: 1000, currency: "usd")

      expect {
        gateway.send(:verify_payment_intent_matches!, intent, 9999, "USD")
      }.to raise_error(PallasTrade::Core::GatewayError, /amount or currency/)
    end

    it "rejects a provider currency that differs from the order currency" do
      intent = payment_intent(amount: 1000, currency: "eur")

      expect {
        gateway.send(:verify_payment_intent_matches!, intent, 1000, "USD")
      }.to raise_error(PallasTrade::Core::GatewayError, /amount or currency/)
    end
  end

  # ── STR-010: Network retry idempotency ────────────────────────────────

  describe "STR-010: Network retry idempotency" do
    it "passes a stable operation-specific idempotency key to Capture" do
      pending_intent = Stripe::PaymentIntent.construct_from(
        id: "pi_capture_retry",
        amount: 1000,
        currency: "usd",
        status: "requires_capture"
      )
      captured_intent = Stripe::PaymentIntent.construct_from(
        id: "pi_capture_retry",
        amount: 1000,
        currency: "usd",
        status: "succeeded"
      )
      allow(gateway).to receive(:retrieve_payment_intent).and_return(pending_intent)
      allow(Stripe::PaymentIntent).to receive(:capture).and_return(captured_intent)

      gateway.capture(1000, "pi_capture_retry", idempotency_key: "pallastrade-pay-123")

      expect(Stripe::PaymentIntent).to have_received(:capture).with(
        "pi_capture_retry",
        { amount_to_capture: 1000 },
        hash_including(idempotency_key: "pallastrade-pay-123-capture")
      )
    end

    it "reuses the refund idempotency key when the same refund is retried" do
      refund = PallasTrade::Refund.new(id: 42)
      request_options = []
      response = Stripe::Refund.construct_from(id: "re_retry", status: "succeeded")
      allow(Stripe::Refund).to receive(:create) do |_payload, options|
        request_options << options
        response
      end

      2.times do
        gateway.credit(500, nil, "pi_refund_retry", originator: refund)
      end

      expect(request_options.map { |options| options[:idempotency_key] }).to eq(
        ["pallastrade-refund-42-credit", "pallastrade-refund-42-credit"]
      )
    end
  end

  # ── STR-011: Unauthorized capture/refund ──────────────────────────────

  describe "STR-011: Unauthorized capture/refund" do
    it "prevents capture of already-captured PaymentIntent" do
      skip_unless_stripe_keys!

      intent = Stripe::PaymentIntent.create(
        amount: 3000,
        currency: "usd",
        payment_method: "pm_card_visa",
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
    it "does not expose private Stripe preferences through public preferences" do
      gateway.preferred_secret_key = "sk_test_super_secret_12345"
      gateway.preferred_publishable_key = "pk_test_public_12345"

      expect(gateway.public_preferences).not_to include(:secret_key, :publishable_key)
      expect(gateway.public_preferences.values.join).not_to include("sk_test_", "pk_test_")
    end

    it "filters Stripe credentials, signatures, and authorization headers" do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter(
        secret_key: "sk_test_super_secret_12345",
        publishable_key: "pk_test_public_12345",
        stripe_signature: "t=123,v1=abcdef",
        authorization: "Bearer sk_test_super_secret_12345"
      )

      expect(filtered.values).to all(eq("[FILTERED]"))
    end

    it "returns a generic webhook error that does not expose its signing secret" do
      secret = "whsec_abc123def456"
      attach_webhook_secret(gateway, secret)
      payload = { type: "payment_intent.succeeded" }.to_json
      headers = { "HTTP_STRIPE_SIGNATURE" => "t=1,v1=invalid" }

      expect {
        gateway.send(:verify_webhook_signature, payload, headers)
      }.to raise_error(PallasTrade::PaymentMethod::WebhookSignatureError) { |error|
        expect(error.message).to eq("Invalid webhook signature")
        expect(error.message).not_to include(secret)
      }
    end

    it "redacts credentials from provider error messages" do
      message = "Invalid API key sk_test_super_secret and Bearer pk_test_public_secret"

      filtered = gateway.send(:filtered_stripe_error_message, message)

      expect(filtered).to eq("Invalid API key [FILTERED] and Bearer [FILTERED]")
      expect(filtered).not_to include("sk_test_", "pk_test_")
    end
  end

  # ── Helper ─────────────────────────────────────────────────────────────

  def attach_webhook_secret(payment_method, secret)
    webhook_key = PallasTradeStripe::WebhookKey.create!(
      stripe_id: "we_#{SecureRandom.hex(8)}",
      signing_secret: secret
    )
    webhook_key.payment_methods << payment_method
    webhook_key
  end

  def stripe_signature_header(payload, secret, timestamp: Time.now.to_i)
    signed_payload = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
    "t=#{timestamp},v1=#{signature}"
  end

  def skip_unless_stripe_keys!
    return if ENV["STRIPE_SECRET_KEY"]&.start_with?("sk_test_")

    skip "STRIPE_SECRET_KEY not set or not a test key. Set STRIPE_SECRET_KEY and STRIPE_PUBLISHABLE_KEY env vars."
  end
end
