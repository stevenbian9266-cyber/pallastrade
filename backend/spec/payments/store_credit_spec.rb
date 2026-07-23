# frozen_string_literal: true

require "spec_helper"

RSpec.describe PallasTrade::StoreCredit, type: :model do
  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:category) { create(:store_credit_category) }
  let(:credit) do
    create(
      :store_credit,
      user: user,
      amount: 100,
      currency: "USD",
      store: store,
      category: category
    )
  end

  it "authorizes and captures funds while recording the ledger events" do
    authorization = credit.authorize(40.to_d, "USD")

    expect(authorization).to be_present
    expect(credit.reload.amount_authorized).to eq(40)
    expect(credit.amount_remaining).to eq(60)

    expect(credit.capture(40.to_d, authorization, "USD")).to eq(authorization)

    credit.reload
    expect(credit.amount_used).to eq(40)
    expect(credit.amount_authorized).to be_zero
    expect(credit.amount_remaining).to eq(60)
    expect(credit.store_credit_events.where(authorization_code: authorization).pluck(:action)).
      to contain_exactly("authorize", "capture")
  end

  it "rejects an authorization that exceeds the available balance" do
    expect(credit.authorize(101.to_d, "USD")).to be(false)
    expect(credit.errors.full_messages).to be_present

    credit.reload
    expect(credit.amount_authorized).to be_zero
    expect(credit.amount_used).to be_zero
  end

  it "voids an authorization and restores the available balance" do
    authorization = credit.authorize(30.to_d, "USD")

    expect(credit.void(authorization)).to be(true)

    credit.reload
    expect(credit.amount_authorized).to be_zero
    expect(credit.amount_remaining).to eq(100)
    expect(credit.store_credit_events.where(authorization_code: authorization).pluck(:action)).
      to contain_exactly("authorize", "void")
  end

  it "restores only the refunded amount after a partial credit" do
    authorization = credit.authorize(40.to_d, "USD")
    credit.capture(40.to_d, authorization, "USD")

    expect(credit.credit(15.to_d, authorization, "USD")).to be(true)

    credit.reload
    expect(credit.amount_used).to eq(25)
    expect(credit.amount_remaining).to eq(75)
    expect(credit.store_credit_events.where(action: "credit", authorization_code: authorization).sum(:amount)).
      to eq(15)
  end

  it "does not duplicate an authorization with the same authorization code" do
    options = { action_authorization_code: "store-credit-idempotency-key" }

    expect(credit.authorize(20.to_d, "USD", options)).to eq("store-credit-idempotency-key")
    expect(credit.authorize(20.to_d, "USD", options)).to be(true)

    credit.reload
    expect(credit.amount_authorized).to eq(20)
    expect(credit.store_credit_events.where(action: "authorize", authorization_code: options[:action_authorization_code]).count).
      to eq(1)
  end

  it "rejects authorization in a different currency" do
    expect(credit.authorize(10.to_d, "EUR")).to be(false)
    expect(credit.reload.amount_authorized).to be_zero
  end

  it "prevents moving an existing credit to another store" do
    other_store = create(:store, code: "store_credit_gate_#{credit.id}")

    expect(credit.update(store: other_store)).to be(false)
    expect(credit.errors[:store]).to be_present
    expect(credit.reload.store).to eq(store)
  end

  it "cannot be deleted after funds have been captured" do
    authorization = credit.authorize(10.to_d, "USD")
    credit.capture(10.to_d, authorization, "USD")

    expect { credit.destroy }.not_to change(PallasTrade::StoreCredit, :count)
    expect(credit.errors[:amount_used]).to be_present
    expect(credit.reload).to be_persisted
  end
end
