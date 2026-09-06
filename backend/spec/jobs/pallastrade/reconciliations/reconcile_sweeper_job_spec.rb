# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-8 AC-4P8-05/06/08
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe PallasTrade::Reconciliations::ReconcileSweeperJob, type: :job do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def make_transaction(state: 'completed')
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: store.default_currency.to_s, amount: 100
    )
    tx.start_payment! if tx.state == 'created'
    tx.confirm_payment! if state == 'payment_confirmed' || state == 'finalizing' || state == 'completed'
    tx.begin_finalizing! if state == 'finalizing' || state == 'completed'
    tx.complete! if state == 'completed'
    tx
  end

  # captured payment（真实证据）——默认不写 journal → JOURNAL_POSTING_MISSING
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

  it 'AC-4P8-05 enqueues RepairTransactionJob for a journal-missing completed transaction' do
    txn = make_transaction(state: 'completed')
    captured_payment(txn: txn)

    expect { described_class.perform_now }.
      to have_enqueued_job(PallasTrade::FinancialLedger::RepairTransactionJob).with(txn.prefixed_id)
  end

  it 'AC-4P8-05 healthy (journal-complete) transactions are not auto-repaired' do
    txn = make_transaction(state: 'completed')
    payment = captured_payment(txn: txn)
    PallasTrade::FinancialLedgerEntry.create!(
      commerce_transaction: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, currency: 'USD',
      idempotency_key: "spec-p48-sweep-#{txn.id}", effective_at: Time.current, payment: payment
    )

    expect { described_class.perform_now }.
      not_to have_enqueued_job(PallasTrade::FinancialLedger::RepairTransactionJob)
  end

  it 'AC-4P8-06 logs structured metrics with status counts and store scope' do
    txn = make_transaction(state: 'completed')
    captured_payment(txn: txn) # needs repair → NEEDS_ATTENTION + enqueue

    infos = []
    allow(Rails.logger).to receive(:info) { |message| infos << message.to_s; true }

    described_class.perform_now(store_id: store.id)

    payload = infos.map { |m| JSON.parse(m) rescue nil }.compact.find { |p| p['event'] == 'reconciliations.sweeper' }
    expect(payload).to be_present
    expect(payload['store_id']).to eq(store.id)
    expect(payload['repair_enqueued']).to eq(1)
    expect(payload['status_counts']).to be_present
  end

  it 'AC-4P8-05/06 mismatch / needs_attention are NOT auto-repaired (human review), only logged' do
    # 真实 mismatch：组合 txn journal cash=100 但 ORDER_ALLOCATION=60 → ALLOCATION_MISMATCH。
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'combined_payment',
                                                   currency: 'USD', amount: 100, payment_combination: combo)
    txn.start_payment! if txn.state == 'created'
    txn.confirm_payment!
    txn.begin_finalizing!
    txn.complete!
    o1 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 60, total: 60,
                        payment_state: 'balance_due')
    s1 = create(:payment_split, payment_combination: combo, order: o1, payment: nil, currency: 'USD',
                                captured_amount: 60)
    PallasTrade::FinancialLedgerEntry.create!(
      commerce_transaction: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, currency: 'USD',
      idempotency_key: "spec-p48-mismatch-cash-#{txn.id}", effective_at: Time.current
    )
    PallasTrade::FinancialLedgerEntry.create!(
      commerce_transaction: txn, entry_type: 'ORDER_ALLOCATION', amount: 60.0, currency: 'USD',
      idempotency_key: "spec-p48-mismatch-alloc-#{txn.id}", effective_at: Time.current, payment_split: s1
    )

    warns = []
    allow(Rails.logger).to receive(:warn) { |message| warns << message.to_s; true }

    expect { described_class.perform_now }.
      not_to have_enqueued_job(PallasTrade::FinancialLedger::RepairTransactionJob)
    expect(warns).to include(a_string_matching(/financial review/))
  end

  it 'AC-4P8-06/08 runs repeatedly without side effects when nothing actionable' do
    expect { described_class.perform_now }.not_to raise_error
    expect { described_class.perform_now }.not_to raise_error
  end
end
