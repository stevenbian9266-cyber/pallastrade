# frozen_string_literal: true

require "spec_helper"

# PRD-20260919-checkout-express-always-visible-and-pi-params AC-002 / AC-008（真机回归守卫）：
# `Gateway#create_payment_session`（Checkout Session 模式）交给 Stripe 的载荷必须通过白名单 ——
# 顶层键、以及 `payment_intent_data` 的子键。dev 真机曾在此撞上
# `parameter_unknown: payment_intent_data[billing_details]`（Stripe 只读字段，上行即 400）。
#
# 说明：全程 stub `Stripe::Checkout::Session.create`，不发真实网络请求。
RSpec.describe PallasTradeStripe::Gateway, "Checkout Session payload guard", type: :model do
  subject(:gateway) { create(:stripe_gateway) }

  let(:order) do
    create(
      :order,
      number: "R123456",
      currency: "USD",
      email: "jane@example.com",
      ship_address: create(:address, address1: "1 Main St", city: "New York", zipcode: "10001", firstname: "Jane", lastname: "Doe"),
      bill_address: create(:address, address1: "1 Billing St", city: "Billingville", zipcode: "10002", firstname: "Jane", lastname: "Doe")
    )
  end

  def stub_customer(result)
    allow(gateway).to receive(:fetch_or_create_customer).and_return(result)
  end

  def stub_session_creation
    captured = { payload: nil }
    allow(Stripe::Checkout::Session).to receive(:create) do |payload, _options|
      captured[:payload] = payload
      double(id: "cs_test_guard", client_secret: "cs_test_guard_secret")
    end
    captured
  end

  describe "#create_payment_session" do
    it "hands Stripe a whitelist-clean Checkout Session payload" do
      stub_customer(double(profile_id: "cus_123"))
      captured = stub_session_creation

      gateway.create_payment_session(
        order: order,
        amount: "129.99",
        external_data: { idempotency_key: "pallastrade-order-test" }
      )

      payload = captured[:payload]
      expect(payload).to be_present
      top_level = payload.keys.map(&:to_sym)
      expect(top_level - PallasTradeStripe::Gateway::CHECKOUT_SESSION_TOP_LEVEL_KEYS).to eq([])

      intent_data = payload[:payment_intent_data].keys.map(&:to_sym)
      expect(intent_data - PallasTradeStripe::Gateway::CHECKOUT_SESSION_PAYMENT_INTENT_DATA_KEYS).to eq([])
      expect(intent_data).not_to include(:billing_details)
    end

    it "refuses to call Stripe when billing_details sneaks into payment_intent_data" do
      stub_customer(double(profile_id: "cus_123"))
      presenter = instance_double(
        PallasTradeStripe::CheckoutSessionPresenter,
        call: {
          mode: "payment",
          ui_mode: "elements",
          line_items: [],
          payment_intent_data: { billing_details: { name: "Jane Doe" } }
        }
      )
      allow(PallasTradeStripe::CheckoutSessionPresenter).to receive(:new).and_return(presenter)
      expect(Stripe::Checkout::Session).not_to receive(:create)

      expect do
        gateway.create_payment_session(order: order, amount: "129.99", external_data: {})
      end.to raise_error(ArgumentError, /billing_details/)
    end

    it "refuses unknown top-level keys as well (whitelist by default)" do
      stub_customer(double(profile_id: "cus_123"))
      presenter = instance_double(
        PallasTradeStripe::CheckoutSessionPresenter,
        call: { mode: "payment", ui_mode: "elements", line_items: [], not_a_stripe_param: true }
      )
      allow(PallasTradeStripe::CheckoutSessionPresenter).to receive(:new).and_return(presenter)
      expect(Stripe::Checkout::Session).not_to receive(:create)

      expect do
        gateway.create_payment_session(order: order, amount: "129.99", external_data: {})
      end.to raise_error(ArgumentError, /not_a_stripe_param/)
    end
  end
end
