# frozen_string_literal: true

# PRD-20260904-api-txn-p2-2 AC-206
require 'rails_helper'

RSpec.describe PallasTrade::Transactions::Resume, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(
      :order,
      store: store,
      state: 'pending',
      status: 'placed',
      submitted_at: Time.current,
      item_total: 8,
      total: 8,
      payment_state: 'balance_due',
      currency: store.default_currency
    )
  end
  let(:tx) do
    PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: store.default_currency, amount: 8.0
    )
  end
  let!(:participant) do
    PallasTrade::TransactionOrder.create!(
      commerce_transaction: tx, order: order, role: 'primary', amount_snapshot: 8.0
    )
  end

  it 'AC-206 resumes a read model with state, participants and sessions (zero side effects)' do
    tx.start_payment!

    result = described_class.call(transaction: tx)
    expect(result).to be_success
    payload = result.value

    expect(payload[:state]).to eq('payment_pending')
    expect(payload[:purpose]).to eq('purchase')
    expect(payload[:participants].size).to eq(1)
    expect(payload[:participants].first[:role]).to eq('primary')
    expect(payload[:participants].first[:order_id]).to eq(order.prefixed_id)
    expect(payload[:recovery][:attempts]).to eq(0)
    expect(payload[:completion][:participants_total]).to eq(1)

    tx.reload
    expect(tx.state).to eq('payment_pending') # 零副作用
  end
end
