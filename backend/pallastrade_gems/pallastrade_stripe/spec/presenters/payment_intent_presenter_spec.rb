# frozen_string_literal: true

require "spec_helper"

# PRD-20260919-checkout-express-always-visible-and-pi-params FR-001 / AC-001：
# PaymentIntent 载荷**永远不含**顶层 `billing_details` —— Stripe 侧该字段是**只读**的
# （仅 retrieve 返回），创建/更新时传入会 400 `parameter_unknown: billing_details`。
# 2026-09-19 dev 事故：该键被合进创建参数 → 全部卡/钱包支付在建会话阶段失败。
#
# 账单详情的三条合法通路（`call` 的载荷一律不得出现该键）：
#   ① 客户端确认时 PM 级 `payment_method.billing_details`（卡表单 / 钱包）；
#   ② Checkout Session 的 `payment_intent_data.billing_details`（CheckoutSessionPresenter）；
#   ③ 支付完成后由 `charge.billing_details` 回读快照。
RSpec.describe PallasTradeStripe::PaymentIntentPresenter, type: :model do
  subject(:presenter) do
    described_class.new(
      amount: 549_99,
      order: order,
      customer: "cus_123"
    )
  end

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

  describe "#call" do
    it "never sends top-level billing_details (read-only Stripe parameter)" do
      expect(presenter.call).not_to have_key(:billing_details)
    end

    it "never sends top-level billing_details even without a shipping address" do
      order.ship_address = nil
      payload = presenter.call

      expect(payload).not_to have_key(:shipping)
      expect(payload).not_to have_key(:billing_details)
    end

    it "never sends top-level billing_details for saved payment methods either" do
      saved = described_class.new(
        amount: 549_99,
        order: order,
        customer: "cus_123",
        payment_method_id: "pm_123",
        off_session: true
      )

      expect(saved.call).not_to have_key(:billing_details)
    end

    it "emits only legal Stripe PaymentIntent top-level keys" do
      keys = presenter.call.keys.map(&:to_sym)

      expect(keys - PallasTradeStripe::Gateway::PaymentIntents::PAYMENT_INTENT_TOP_LEVEL_KEYS).to eq([])
      expect(keys).not_to include(:billing_details)
    end

    # 构造器本身仍可用（供其它**合法载体**复用，如 payment_method_data / payment_intent_data），
    # 但 `call` 的载荷绝不能带上它 —— 见上方 AC-001 断言。
    it "still exposes billing_details for legal carriers only" do
      expect(presenter.billing_details_payload[:billing_details][:address][:line1]).to eq("1 Billing St")
    end

    it "returns nil from billing_details_payload when the billing address is unusable" do
      order.bill_address = nil

      expect(presenter.billing_details_payload).to be_nil
    end
  end
end
