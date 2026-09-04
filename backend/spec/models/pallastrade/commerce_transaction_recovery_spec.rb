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
end
