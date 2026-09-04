# frozen_string_literal: true

# PRD-20260904-payments-txn-p2-4 AC-421/422
require 'rails_helper'

RSpec.describe PallasTrade::Transactions::RecoverJob, type: :job do
  let(:store) { @default_store }

  def make_recovery_required
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: store.default_currency.to_s, amount: 100
    )
    tx.start_payment!
    tx.confirm_payment!
    tx.mark_recovery_required!
    tx
  end

  describe '#perform' do
    it 'AC-421 executes Recover for a recovery_required transaction (UNPAID → payment_pending)' do
      tx = make_recovery_required # 无 session → resolver unpaid

      expect { described_class.perform_now(tx.prefixed_id) }.
        not_to raise_error
      expect(tx.reload).to be_payment_pending
    end

    it 'AC-422 discards on RecordNotFound (BaseJob semantics)' do
      expect { described_class.perform_now('txn_missing_123') }.not_to raise_error
    end
  end
end
