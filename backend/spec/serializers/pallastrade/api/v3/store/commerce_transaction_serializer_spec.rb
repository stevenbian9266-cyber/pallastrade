# frozen_string_literal: true

# PRD-20260905-other-txn-p2-closure AC-801/802
require 'rails_helper'

RSpec.describe PallasTrade::Api::V3::Store::CommerceTransactionSerializer, type: :model do
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }

  def make_transaction(state: 'payment_pending')
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: 'USD', amount: 100
    )
    tx.update_columns(
      checkout_version: 3, price_version: 'pv_1', snapshot_fingerprint: 'fp_1',
      recovery_attempts: 1, last_error_code: nil
    )
    tx.start_payment! if state == 'payment_pending'
    tx.reload
  end

  def serialize(transaction)
    described_class.new(transaction, params: {}).to_h
  end

  describe '#to_h (AC-801/802)' do
    it 'outputs prefixed id and core attributes matching the P2-2 create payload' do
      tx = make_transaction

      data = serialize(tx)

      expect(data['id']).to eq(tx.prefixed_id)
      expect(data['state']).to eq('payment_pending')
      expect(data['purpose']).to eq('purchase')
      expect(data['currency']).to eq('USD')
      expect(data['amount']).to eq('100.0')
      expect(data['checkout_version']).to eq(3)
      expect(data['price_version']).to eq('pv_1')
      expect(data['snapshot_fingerprint']).to eq('fp_1')
    end

    it 'outputs lifecycle timestamps as ISO strings and recovery metadata' do
      tx = make_transaction(state: 'payment_pending')
      tx.update_columns(started_at: Time.utc(2026, 9, 5, 1, 0, 0),
                        payment_confirmed_at: Time.utc(2026, 9, 5, 1, 1, 0),
                        completed_at: nil)

      data = serialize(tx.reload)

      expect(data['started_at']).to eq('2026-09-05T01:00:00Z')
      expect(data['payment_confirmed_at']).to eq('2026-09-05T01:01:00Z')
      expect(data['completed_at']).to be_nil
      expect(data['recovery_attempts']).to eq(1)
      expect(data['last_error_code']).to be_nil
    end
  end
end
