# frozen_string_literal: true

require "spec_helper"

# PRD-20260919-checkout-express-always-visible-and-pi-params FR-001 / AC-001（回归守卫）：
# `Gateway#create_payment_intent` / `#update_payment_intent` 交给 Stripe 的**顶层载荷**
# 必须是白名单内合法键；Stripe 只读字段（尤其 `billing_details`）出现即本地抛错，
# 绝不允许再次以 400 `parameter_unknown` 的形式把线上支付全线打死（2026-09-19 事故）。
#
# 说明：本 spec 全程 stub `Stripe::PaymentIntent.*`，不发真实网络请求。
RSpec.describe PallasTradeStripe::Gateway, "PaymentIntent payload guard", type: :model do
  subject(:gateway) { create(:stripe_gateway) }

  let(:order) do
    build(
      :order,
      number: "R123456",
      currency: "USD",
      email: "jane@example.com",
      ship_address: build(:address, address1: "1 Main St", city: "New York", zipcode: "10001", firstname: "Jane", lastname: "Doe"),
      bill_address: build(:address, address1: "1 Billing St", city: "Billingville", zipcode: "EC1A 1BB", firstname: "Jane", lastname: "Doe")
    )
  end

  describe "#create_payment_intent" do
    it "hands Stripe a whitelist-clean payload without read-only billing_details" do
      captured = nil
      allow(Stripe::PaymentIntent).to receive(:create) do |payload, _options|
        captured = payload
        double(id: "pi_test_guard")
      end

      gateway.create_payment_intent(54_999, order, customer_profile_id: "cus_123")

      expect(captured).to be_present
      keys = captured.keys.map(&:to_sym)
      expect(keys).not_to include(:billing_details)
      expect(keys - described_class::PaymentIntents::PAYMENT_INTENT_TOP_LEVEL_KEYS).to eq([])
    end

    it "refuses to call Stripe when a read-only key sneaks into the payload" do
      presenter = instance_double(
        PallasTradeStripe::PaymentIntentPresenter,
        call: { amount: 54_999, currency: "USD", billing_details: { name: "Jane Doe" } }
      )
      allow(PallasTradeStripe::PaymentIntentPresenter).to receive(:new).and_return(presenter)
      expect(Stripe::PaymentIntent).not_to receive(:create)

      expect { gateway.create_payment_intent(54_999, order, customer_profile_id: "cus_123") }
        .to raise_error(ArgumentError, /billing_details/)
    end

    it "refuses unknown top-level keys as well (whitelist by default)" do
      presenter = instance_double(
        PallasTradeStripe::PaymentIntentPresenter,
        call: { amount: 54_999, currency: "USD", not_a_stripe_param: true }
      )
      allow(PallasTradeStripe::PaymentIntentPresenter).to receive(:new).and_return(presenter)
      expect(Stripe::PaymentIntent).not_to receive(:create)

      expect { gateway.create_payment_intent(54_999, order, customer_profile_id: "cus_123") }
        .to raise_error(ArgumentError, /not_a_stripe_param/)
    end
  end

  describe "#update_payment_intent" do
    it "updates with the sliced, whitelist-clean payload only" do
      # 该路径没有 customer_profile_id 入参 → 先挡掉客户档案的远端解析（避免真实 API 调用）
      allow(gateway).to receive(:fetch_or_create_customer)
        .and_return(double(profile_id: "cus_123"))
      captured = nil
      allow(Stripe::PaymentIntent).to receive(:update) do |_id, payload, _options|
        captured = payload
        double(id: "pi_test_guard")
      end

      gateway.update_payment_intent("pi_test_guard", 54_999, order)

      # 白名单子集（update 路径按 `.slice` 固定为这 5 个键）
      expect(captured.keys.map(&:to_sym))
        .to contain_exactly(:amount, :currency, :customer, :shipping)
      expect(captured.keys.map(&:to_sym)).not_to include(:billing_details)
    end
  end
end
