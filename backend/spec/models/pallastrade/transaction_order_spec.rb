# frozen_string_literal: true

# PRD-20260904-checkout-txn-p2-1 AC-203
require 'rails_helper'

RSpec.describe PallasTrade::TransactionOrder, type: :model do
  let!(:store) { create(:store, code: 'txn21_to_store') }
  let(:user) { create(:user) }
  let(:order1) { create(:order_with_line_items, store: store, user: user, shipment_cost: 0) }
  let(:order2) { create(:order_with_line_items, store: store, user: user, shipment_cost: 0) }
  let(:tx) do
    PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'combined_payment',
      currency: store.default_currency, amount: 20.0
    )
  end

  def add(order, role: 'participant', amount: 10.0)
    described_class.create!(
      commerce_transaction: tx, order: order, role: role,
      amount_snapshot: amount, completion_status: 'pending'
    )
  end

  it 'AC-203 links one transaction to multiple orders with roles and amount snapshot' do
    p1 = add(order1, role: 'primary', amount: 12.0)
    add(order2, role: 'participant', amount: 8.0)

    expect(tx.transaction_orders.count).to eq(2)
    expect(tx.orders.map(&:id)).to contain_exactly(order1.id, order2.id)
    expect(p1.role).to eq('primary')
    expect(p1.amount_snapshot).to eq(12.0)
    expect(p1.completion_status).to eq('pending')
  end

  it 'AC-203 rejects an unknown role' do
    expect do
      described_class.create!(
        commerce_transaction: tx, order: order1, role: 'fulfillment_child',
        amount_snapshot: 10.0
      )
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'AC-203 unique [transaction_id, order_id] prevents duplicate attachment' do
    add(order1, role: 'primary')
    expect do
      described_class.create!(
        commerce_transaction: tx, order: order1, role: 'participant', amount_snapshot: 10.0
      )
    end.to raise_error(ActiveRecord::RecordInvalid)
  end
end
