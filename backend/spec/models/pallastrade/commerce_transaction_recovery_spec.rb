# frozen_string_literal: true

# PRD-20260904-payments-txn-p2-4 AC-401/402/403
require 'rails_helper'

RSpec.describe PallasTrade::CommerceTransaction, type: :model do
  let(:store) { @default_store }

  def make_transaction
    PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: store.default_currency.to_s, amount: 100
    )
  end

  def make_recovery_required
    tx = make_transaction
    tx.start_payment!
    tx.confirm_payment!
    tx.mark_recovery_required!
    tx
  end

  describe 'recovery exit state machine (TXN-P2-4)' do
    it 'AC-401 retry_payment! moves recovery_required → payment_pending' do
      tx = make_recovery_required

      expect { tx.retry_payment! }.not_to raise_error
      expect(tx.reload).to be_payment_pending
    end

    it 'AC-401 retry_payment! is rejected outside recovery_required' do
      tx = make_transaction
      tx.start_payment!

      expect { tx.retry_payment! }.
        to raise_error(PallasTrade::CommerceTransaction::InvalidTransitionError)
      expect(tx.reload).to be_payment_pending
    end

    it 'AC-402 retry_finalizing! and repair_completed! only from recovery_required' do
      tx = make_recovery_required
      expect { tx.retry_finalizing! }.not_to raise_error
      expect(tx.reload).to be_finalizing

      other = make_recovery_required
      expect { other.repair_completed! }.not_to raise_error
      expect(other.reload).to be_completed
      expect(other.completed_at).to be_present
    end

    it 'AC-403 payment_confirmed cannot retry_payment (INV-02)' do
      tx = make_transaction
      tx.start_payment!
      tx.confirm_payment!

      expect { tx.retry_payment! }.
        to raise_error(PallasTrade::CommerceTransaction::InvalidTransitionError)
      expect(tx.reload).to be_payment_confirmed
    end

    it 'AC-2011 path: mark_recovery_required! from payment_confirmed records recovery_required_at' do
      tx = make_transaction
      tx.start_payment!
      tx.confirm_payment!

      expect { tx.mark_recovery_required! }.not_to raise_error
      expect(tx.reload).to be_recovery_required
      expect(tx.recovery_required_at).to be_present
    end
  end

  describe 'operational hardening (TXN-P2-7)' do
    describe '.needs_attention' do
      it 'AC-701 recovery_required / manual_review are always included' do
        recovery = make_recovery_required
        manual = make_recovery_required
        manual.manual_review!

        expect(described_class.needs_attention).to include(recovery, manual)
      end

      it 'AC-702 payment_confirmed older than threshold is included; fresh one is not' do
        stale = make_transaction
        stale.start_payment!
        stale.confirm_payment!
        stale.update_columns(updated_at: 2.hours.ago)

        fresh = make_transaction
        fresh.start_payment!
        fresh.confirm_payment!

        relation = described_class.needs_attention
        expect(relation).to include(stale)
        expect(relation).not_to include(fresh)
      end

      it 'AC-703 terminal / pending / created are excluded and stuck_after param applies' do
        created = make_transaction
        pending = make_transaction
        pending.start_payment!
        completed = make_transaction
        completed.update_columns(state: 'completed', completed_at: Time.current)

        relation = described_class.needs_attention
        expect(relation).not_to include(created, pending, completed)

        stale = make_transaction
        stale.start_payment!
        stale.confirm_payment!
        stale.update_columns(updated_at: 2.hours.ago)
        expect(described_class.needs_attention(stuck_after: 3.hours)).not_to include(stale)
      end
    end

    describe '#trace' do
      it 'AC-711 aggregates timestamps / attempts / error / participants / sessions' do
        tx = make_recovery_required
        tx.update_columns(recovery_attempts: 2, last_error_code: 'finalize_failed',
                          last_error_message: 'boom')

        trace = tx.trace

        expect(trace[:state]).to eq('recovery_required')
        expect(trace[:amount]).to eq('100.0')
        expect(trace[:recovery_required_at]).to be_present
        expect(trace[:recovery_attempts]).to eq(2)
        expect(trace[:last_error_code]).to eq('finalize_failed')
        expect(trace[:last_error_message]).to eq('boom')
        expect(trace[:participants]).to eq(total: 0, completed: 0, roles: {})
        expect(trace[:payment_sessions]).to eq(total: 0, by_status: {})
      end
    end
  end
end
