# frozen_string_literal: true

require "spec_helper"

# PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): after migrating to
# Checkout Sessions the session stores a `cs_` external_id. These specs verify
# the duck-type interface (used by CompleteOrder / CreatePayment) resolves the
# underlying PaymentIntent from the Checkout Session.
RSpec.describe PallasTrade::PaymentSessions::Stripe, type: :model do
  # Use a real (factory-built) Stripe gateway as the AR association, then stub
  # the network calls on it.
  let(:gateway) { create(:stripe_gateway) }
  let(:session) do
    described_class.new(
      order: order,
      payment_method: gateway,
      amount: 100,
      currency: "USD",
      status: "pending",
      external_id: "cs_test_123",
      external_data: { "client_secret" => "cs_test_secret" }
    )
  end
  let(:order) { build(:order, number: "R123456", currency: "USD") }

  let(:fake_payment_intent) do
    Struct.new(:id, :status, :latest_charge, :amount, :currency).new(
      "pi_test_456", "succeeded", "ch_test_789", 10_000, "usd"
    )
  end

  def fake_checkout_session(payment_status:, payment_intent:)
    Struct.new(:id, :payment_status, :payment_intent).new(
      "cs_test_123", payment_status, payment_intent
    )
  end

  describe "#client_secret" do
    it "reads from external_data" do
      expect(session.client_secret).to eq("cs_test_secret")
    end
  end

  describe "#stripe_checkout_session" do
    it "retrieves the Checkout Session by external_id" do
      cs = fake_checkout_session(payment_status: "paid", payment_intent: fake_payment_intent)
      allow(gateway).to receive(:retrieve_checkout_session).with("cs_test_123").and_return(cs)

      expect(session.stripe_checkout_session).to eq(cs)
      expect(gateway).to have_received(:retrieve_checkout_session).with("cs_test_123")
    end
  end

  describe "#stripe_payment_intent" do
    it "returns the intent expanded from the Checkout Session" do
      cs = fake_checkout_session(payment_status: "paid", payment_intent: fake_payment_intent)
      allow(gateway).to receive(:retrieve_checkout_session).and_return(cs)

      expect(session.stripe_payment_intent.id).to eq("pi_test_456")
    end
  end

  describe "#successful?" do
    it "is true when the Checkout Session payment_status is paid" do
      allow(gateway).to receive(:retrieve_checkout_session)
        .and_return(fake_checkout_session(payment_status: "paid", payment_intent: fake_payment_intent))

      expect(session).to be_successful
    end

    it "is false when payment_status is unpaid" do
      allow(gateway).to receive(:retrieve_checkout_session)
        .and_return(fake_checkout_session(payment_status: "unpaid", payment_intent: nil))

      expect(session).not_to be_successful
    end
  end

  describe "#accepted?" do
    it "delegates to the gateway payment_intent_accepted?" do
      allow(gateway).to receive(:retrieve_checkout_session)
        .and_return(fake_checkout_session(payment_status: "paid", payment_intent: fake_payment_intent))
      allow(gateway).to receive(:payment_intent_accepted?).with(fake_payment_intent).and_return(true)

      expect(session.accepted?).to be(true)
    end
  end

  # PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
  # PaymentIntent 模式（自绘卡字段）external_id 直存 `pi_` id——不再经过
  # Checkout Session，直接 retrieve PaymentIntent。
  describe "PaymentIntent mode (external_id 以 pi_ 开头)" do
    let(:pi_session) do
      described_class.new(
        order: order,
        payment_method: gateway,
        amount: 100,
        currency: "USD",
        status: "pending",
        external_id: "pi_test_789",
        external_data: { "client_secret" => "pi_test_789_secret_abc", "mode" => "payment_intent" }
      )
    end

    describe "#payment_intent_mode?" do
      it "is true for pi_ ids and false for cs_ ids" do
        expect(pi_session.payment_intent_mode?).to be(true)
        expect(session.payment_intent_mode?).to be(false)
      end
    end

    describe "#stripe_payment_intent" do
      it "retrieves the PaymentIntent directly (not via Checkout Session)" do
        allow(gateway).to receive(:retrieve_payment_intent).with("pi_test_789").and_return(fake_payment_intent)

        expect(pi_session.stripe_payment_intent.id).to eq("pi_test_456")
        expect(gateway).to have_received(:retrieve_payment_intent).with("pi_test_789")
        expect(gateway).not_to have_received(:retrieve_checkout_session)
      end
    end

    describe "#successful?" do
      it "is true when the PaymentIntent status is succeeded" do
        allow(gateway).to receive(:retrieve_payment_intent).and_return(fake_payment_intent)

        expect(pi_session).to be_successful
      end

      it "is false when the PaymentIntent is not succeeded" do
        pending_intent = Struct.new(:id, :status, :latest_charge, :amount, :currency)
          .new("pi_test_789", "requires_payment_method", nil, 10_000, "usd")
        allow(gateway).to receive(:retrieve_payment_intent).and_return(pending_intent)

        expect(pi_session).not_to be_successful
      end
    end
  end
end
