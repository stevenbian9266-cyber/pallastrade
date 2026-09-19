# frozen_string_literal: true

require "spec_helper"

# PRD-20260919-checkout-billing-details-passthrough AC-001：
# PaymentIntent 载荷必须在有账单地址时带 `billing_details`，缺失时**整体不发**该键
# （不发空对象、不发半空地址），且与配送地址互不依赖。
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
    it "includes billing_details built from the order's billing address" do
      billing = presenter.call[:billing_details]

      expect(billing[:name]).to eq("Jane Doe")
      expect(billing[:email]).to eq("jane@example.com")
      expect(billing[:address][:line1]).to eq("1 Billing St")
      expect(billing[:address][:city]).to eq("Billingville")
      expect(billing[:address][:postal_code]).to eq("EC1A 1BB")
      expect(billing[:address][:country]).to be_present
    end

    it "does not send the key at all when the billing address is missing" do
      order.bill_address = nil

      expect(presenter.call).not_to have_key(:billing_details)
    end

    it "does not send a half-empty billing address" do
      order.bill_address.address1 = nil

      expect(presenter.call).not_to have_key(:billing_details)
    end

    it "still sends billing_details when there is no shipping address" do
      order.ship_address = nil
      payload = presenter.call

      expect(payload).not_to have_key(:shipping)
      expect(payload[:billing_details][:address][:line1]).to eq("1 Billing St")
    end
  end
end
