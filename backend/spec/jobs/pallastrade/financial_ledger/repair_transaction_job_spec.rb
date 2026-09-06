# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-8 AC-4P8-01/03
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe PallasTrade::FinancialLedger::RepairTransactionJob, type: :job do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def captured_payment(txn:)
    pm = create(:bogus_payment_method, store: store, active: true)
    session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'completed',
                                             amount: 100, currency: 'USD', commerce_transaction: txn)
    payment = create(:payment, order: order, payment_method: pm, amount: 100,
                               state: 'completed', payment_session: session,
                               source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)
    payment
  end

  it 'AC-4P8-01 repairs a missing journal entry when driven via job' do
    txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase',
                                                   currency: 'USD', amount: 100)
    captured_payment(txn: txn)

    expect { described_class.perform_now(txn.prefixed_id) }.
      to change(PallasTrade::FinancialLedgerEntry, :count).by(1)
    entry = PallasTrade::FinancialLedgerEntry.last
    expect(entry.entry_type).to eq('CASH_CAPTURED')
    expect(entry.commerce_transaction).to eq(txn)
  end

  it 'AC-4P8-03 is idempotent when run twice' do
    txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase',
                                                   currency: 'USD', amount: 100)
    captured_payment(txn: txn)

    described_class.perform_now(txn.prefixed_id)
    expect { described_class.perform_now(txn.prefixed_id) }.
      not_to(change { PallasTrade::FinancialLedgerEntry.count })
  end

  it 'discards gracefully on unknown transaction id' do
    expect { described_class.perform_now('txn_missing') }.not_to raise_error
  end
end
