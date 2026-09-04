# frozen_string_literal: true

# PRD-20260904-checkout-txn-p2-1 AC-205
require 'rails_helper'

RSpec.describe 'CommerceTransaction snapshot freeze (AC-205)', type: :model do
  let!(:store) { create(:store, code: 'txn21_snap_store') }

  def build_tx
    PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: store.default_currency, amount: 99.0
    )
  end

  it 'AC-205 snapshot! freezes quote binding fields + immutable data' do
    tx = build_tx
    tx.snapshot!(
      checkout_version: 3,
      price_version: 'pv-abc',
      fingerprint: 'fp-123',
      data: { 'order_id' => 'or_x', 'items' => [] }
    )

    tx.reload
    expect(tx.checkout_version).to eq(3)
    expect(tx.price_version).to eq('pv-abc')
    expect(tx.snapshot_fingerprint).to eq('fp-123')
    expect(tx.snapshot_data).to eq('order_id' => 'or_x', 'items' => [])
    expect(tx.snapshot_frozen?).to be true
  end

  it 'AC-205 a second snapshot! raises SnapshotAlreadyFrozen and does not overwrite' do
    tx = build_tx
    tx.snapshot!(checkout_version: 1, price_version: 'v1', fingerprint: 'f1', data: { 'a' => 1 })

    expect do
      tx.snapshot!(checkout_version: 2, price_version: 'v2', fingerprint: 'f2', data: { 'b' => 2 })
    end.to raise_error(PallasTrade::CommerceTransaction::SnapshotAlreadyFrozen)

    tx.reload
    expect(tx.snapshot_fingerprint).to eq('f1')
    expect(tx.snapshot_data).to eq('a' => 1)
    expect(tx.checkout_version).to eq(1)
  end
end
