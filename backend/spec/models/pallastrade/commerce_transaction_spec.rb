# frozen_string_literal: true

# PRD-20260904-checkout-txn-p2-1 AC-201/202/204/206/207
require 'rails_helper'

RSpec.describe PallasTrade::CommerceTransaction, type: :model do
  let!(:store) { create(:store, code: 'txn21_store') }
  let(:user) { create(:user) }
  let(:order) { create(:order_with_line_items, store: store, user: user, shipment_cost: 0) }

  def build_tx(purpose: 'purchase', amount: 10.0)
    described_class.create!(
      store: store, purpose: purpose,
      currency: store.default_currency, amount: amount
    )
  end

  describe 'state machine' do
    it 'AC-201 walks created → payment_pending → payment_confirmed → finalizing → completed' do
      tx = build_tx
      expect(tx.state).to eq('created')

      tx.start_payment!
      expect(tx.state).to eq('payment_pending')
      expect(tx.started_at).to be_present

      tx.confirm_payment!
      expect(tx.state).to eq('payment_confirmed')
      expect(tx.payment_confirmed_at).to be_present

      tx.begin_finalizing!
      expect(tx.state).to eq('finalizing')
      expect(tx.finalizing_at).to be_present

      tx.complete!
      expect(tx.state).to eq('completed')
      expect(tx.completed_at).to be_present
    end

    it 'AC-201 blocks payment_confirmed → payment_pending (INV-02/03)' do
      tx = build_tx
      tx.start_payment!
      tx.confirm_payment!
      expect { tx.start_payment! }.to raise_error(
        PallasTrade::CommerceTransaction::InvalidTransitionError
      ) do |e|
        expect(e.code).to eq('commerce_transaction_cannot_start_payment')
      end
      expect(tx.state).to eq('payment_confirmed')
    end

    it 'AC-202 supports cancel / recovery_required / manual_review with timestamps' do
      canceled = build_tx
      canceled.cancel!
      expect(canceled.state).to eq('canceled')
      expect(canceled.canceled_at).to be_present

      tx = build_tx
      tx.start_payment!
      tx.confirm_payment!
      tx.mark_recovery_required!
      expect(tx.state).to eq('recovery_required')
      expect(tx.recovery_required_at).to be_present

      tx.manual_review!
      expect(tx.state).to eq('manual_review')
      expect(tx.manual_review_at).to be_present
    end

    it 'AC-206 publishes transition audit events' do
      tx = build_tx
      allow(tx).to receive(:publish_event).and_call_original
      expect(tx).to receive(:publish_event).with('commerce_transaction.payment_started').and_call_original
      expect(tx).to receive(:publish_event).with('commerce_transaction.payment_confirmed').and_call_original
      tx.start_payment!
      tx.confirm_payment!
    end
  end

  describe 'purpose' do
    it 'AC-204 accepts purchase / balance_collection / combined_payment' do
      expect(build_tx(purpose: 'balance_collection').purpose).to eq('balance_collection')
      expect(build_tx(purpose: 'combined_payment').purpose).to eq('combined_payment')
    end

    it 'AC-204 rejects an unknown purpose' do
      expect { build_tx(purpose: 'bogus') }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '.active_for_order' do
    it 'AC-207 returns the active transaction for an order + purpose' do
      tx = build_tx
      PallasTrade::TransactionOrder.create!(
        commerce_transaction: tx, order: order, role: 'primary', amount_snapshot: 10.0
      )
      tx.start_payment!

      expect(described_class.active_for_order(order, purpose: 'purchase').id).to eq(tx.id)
    end

    it 'AC-207 returns nil once the transaction leaves active states' do
      tx = build_tx
      PallasTrade::TransactionOrder.create!(
        commerce_transaction: tx, order: order, role: 'primary', amount_snapshot: 10.0
      )
      tx.start_payment!
      tx.confirm_payment!
      tx.begin_finalizing!
      tx.complete!

      expect(described_class.active_for_order(order, purpose: 'purchase')).to be_nil
    end
  end

  describe '#record_recovery_failure' do
    it 'increments recovery_attempts and records last error metadata' do
      tx = build_tx
      tx.record_recovery_failure(error_class: 'ActiveRecord::LockWaitTimeout', code: 'lock_wait', message: 'boom')
      tx.record_recovery_failure(error_class: 'RuntimeError')

      expect(tx.recovery_attempts).to eq(2)
      expect(tx.last_error_class).to eq('RuntimeError')
      expect(tx.last_error_code).to eq('lock_wait') # 保留首次 code
      expect(tx.last_error_message).to eq('boom')
    end
  end
end
