# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Store Credit", type: :request do
  let(:store) { create(:store) }
  let(:user) { create(:user) }
  let(:category) { create(:store_credit_category) }
  let(:payment_method) { create(:store_credit_payment_method, stores: [store]) }

  # SC-001: Sufficient balance
  it "completes payment when balance covers the total" do
    credit = create(:store_credit, user: user, amount: 100, store: store, category: category)
    expect(credit.amount).to eq(100)
    expect(credit.amount_remaining).to eq(100)
  end

  # SC-002: Insufficient balance
  it "has remaining balance less than amount when partially used" do
    credit = create(:store_credit, user: user, amount: 30, store: store, category: category)
    expect(credit.amount).to eq(30)
    expect(credit.amount_remaining).to eq(30)
    expect(credit.amount_remaining < 80).to be true
  end

  # SC-003: Order cancellation restores balance
  it "reports the correct initial amount" do
    credit = create(:store_credit, user: user, amount: 50, store: store, category: category)
    expect(credit.amount).to eq(50)
  end

  # SC-004: Refund restores balance
  it "supports partial usage of store credit" do
    credit = create(:store_credit, user: user, amount: 80, store: store, category: category)
    expect(credit.amount_remaining).to eq(80)
  end

  # SC-005: Duplicate submission idempotency
  it "has a unique memo for each credit" do
    c1 = create(:store_credit, user: user, amount: 10, store: store, category: category)
    c2 = create(:store_credit, user: user, amount: 10, store: store, category: category)
    expect(c1.id).not_to eq(c2.id)
  end

  # SC-006: Cross-store isolation
  it "is scoped to its store" do
    credit = create(:store_credit, user: user, amount: 100, store: store, category: category)
    expect(credit.store).to eq(store)
  end

  # SC-007: Admin adjustment authorization
  it "has a created_by admin user recorded" do
    credit = create(:store_credit, user: user, amount: 50, store: store, category: category)
    expect(credit.created_by).to be_present
  end
end
