# frozen_string_literal: true

require "spec_helper"

# PRD-20260919-checkout-billing-details-passthrough AC-001/AC-002：
# 账单详情唯一构造点 —— 有账单地址则输出 Stripe `billing_details` 形状；
# 地址缺失或最小完整集不齐 → nil（调用方整体不发，不得发半空地址）。
RSpec.describe PallasTradeStripe::BillingDetailsPresenter, type: :model do
  subject(:payload) { described_class.new(order: order).call }

  let(:order) do
    build(
      :order,
      number: "R123456",
      email: "jane@example.com",
      bill_address: build(
        :address,
        firstname: "Jane",
        lastname: "Doe",
        address1: "1 Billing St",
        address2: "Apt 4",
        city: "Billingville",
        zipcode: "EC1A 1BB",
        phone: "555-0100"
      )
    )
  end

  describe "#call" do
    it "returns the Stripe billing_details shape from the order's billing address" do
      expect(payload[:name]).to eq("Jane Doe")
      expect(payload[:email]).to eq("jane@example.com")
      expect(payload[:phone]).to eq("555-0100")
      # 国家/州用工厂默认的 US/NY 对（真实 Country/State 关联派生，不在本 spec 重造）
      expect(payload[:address]).to include(
        city: "Billingville",
        line1: "1 Billing St",
        line2: "Apt 4",
        postal_code: "EC1A 1BB",
        country: "US"
      )
      expect(payload[:address][:state]).to be_present
    end

    it "drops absent optional keys instead of sending blank strings" do
      order.bill_address.address2 = nil
      order.bill_address.phone = nil
      order.email = nil

      expect(payload[:address]).not_to have_key(:line2)
      expect(payload).not_to have_key(:phone)
      expect(payload).not_to have_key(:email)
    end

    it "returns nil when the order has no billing address" do
      order.bill_address = nil
      expect(payload).to be_nil
    end

    it "returns nil when billing address line1 is blank (incomplete address)" do
      order.bill_address.address1 = nil
      expect(payload).to be_nil
    end
  end
end
