# frozen_string_literal: true

require "spec_helper"

RSpec.describe PallasTradeStripe::CheckoutSessionPresenter, type: :model do
  subject(:presenter) do
    described_class.new(
      amount_in_cents: 549_99,
      order: order,
      customer: "cus_123",
      return_url: "https://example.test/confirm",
      capture_method: "automatic"
    )
  end

  let(:order) do
    build(
      :order,
      number: "R123456",
      currency: "USD",
      email: "jane@example.com",
      ship_address: build(:address, address1: "1 Main St", city: "New York", zipcode: "10001", first_name: "Jane", last_name: "Doe")
    )
  end

  describe "#call" do
    it "builds a one-time payment Checkout Session with ui_mode elements" do
      payload = presenter.call

      expect(payload[:mode]).to eq("payment")
      expect(payload[:ui_mode]).to eq("elements")
      expect(payload[:customer]).to eq("cus_123")
      # customer 与 customer_email 互斥：存在 customer 时不传 customer_email
      expect(payload).not_to have_key(:customer_email)
      expect(payload[:return_url]).to eq("https://example.test/confirm")
    end

    it "passes customer_email when no Stripe customer exists (guest)" do
      guest = described_class.new(
        amount_in_cents: 100,
        order: build(:order, number: "R888", email: "guest@example.com")
      ).call
      expect(guest[:customer_email]).to eq("guest@example.com")
      expect(guest).not_to have_key(:customer)
    end

    it "omits customer_email when the order has no email" do
      payload = described_class.new(
        amount_in_cents: 100,
        order: build(:order, number: "R999", email: nil)
      ).call
      expect(payload).not_to have_key(:customer_email)
    end

    it "adds a single aggregated line item for the amount" do
      line_item = presenter.call[:line_items].first

      expect(line_item[:quantity]).to eq(1)
      expect(line_item[:price_data][:currency]).to eq("USD")
      expect(line_item[:price_data][:unit_amount]).to eq(549_99)
      expect(line_item[:price_data][:product_data][:name]).to eq("R123456")
    end

    it "keeps transfer_group + metadata on payment_intent_data (order accounting)" do
      pid = presenter.call[:payment_intent_data]

      expect(pid[:transfer_group]).to eq("R123456")
      expect(pid[:metadata][:pallastrade_order_id]).to eq(order.id)
      expect(pid[:setup_future_usage]).to eq("off_session")
    end

    it "does NOT force manual capture when capture_method is automatic" do
      expect(presenter.call[:payment_intent_data]).not_to have_key(:capture_method)
    end

    it "forces manual capture when capture_method is manual" do
      manual = described_class.new(
        amount_in_cents: 100,
        order: order,
        capture_method: "manual"
      ).call

      expect(manual[:payment_intent_data][:capture_method]).to eq("manual")
    end

    it "includes the shipping address on payment_intent_data when present" do
      shipping = presenter.call[:payment_intent_data][:shipping]

      expect(shipping[:name]).to eq("Jane Doe")
      expect(shipping[:address][:line1]).to eq("1 Main St")
      expect(shipping[:address][:city]).to eq("New York")
    end

    it "omits return_url when absent" do
      payload = described_class.new(amount_in_cents: 100, order: order).call
      expect(payload).not_to have_key(:return_url)
    end
  end
end
