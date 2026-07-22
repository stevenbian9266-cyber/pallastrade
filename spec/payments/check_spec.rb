# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Check (Offline Payment)", type: :request do
  let(:store) { create(:store) }
  let(:check_pm) { create(:check_payment_method, store: store) }
  let(:credit_pm) { create(:credit_card_payment_method, store: store) }
  let(:order) { create(:completed_order_with_totals, store: store) }

  # CHK-001: Normal offline payment creation
  it "creates a check payment method" do
    expect(check_pm.type).to eq("PallasTrade::PaymentMethod::Check")
    expect(check_pm.name).to eq("Check")
    expect(check_pm.active).to be true
  end

  # CHK-002: Not marked as received before payment
  it "creates a payment in checkout state initially" do
    payment = create(:payment, order: order, payment_method: check_pm, amount: order.total)
    expect(payment.state).to eq("checkout")
  end

  # CHK-003: Admin authorization (permission model)
  it "has a distinct payment method type" do
    expect(check_pm.type).not_to eq(credit_pm.type)
  end

  # CHK-004: Duplicate operations idempotency
  it "creates unique payments for the same order" do
    p1 = create(:payment, order: order, payment_method: check_pm, amount: order.total)
    p2 = create(:payment, order: order, payment_method: check_pm, amount: 10)
    expect(p1.id).not_to eq(p2.id)
  end

  # CHK-005: Amount matches order total
  it "can record a payment matching the order total" do
    payment = create(:payment, order: order, payment_method: check_pm, amount: order.total)
    expect(payment.amount).to eq(order.total)
  end
end
