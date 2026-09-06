# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-7 AC-4P7-01~08/10/11
require 'rails_helper'

module PallasTrade
  class PaymentMethod::ReconcileTransactionProbe < PaymentMethod
    def source_required?
      false
    end
  end
end

RSpec.describe PallasTrade::Reconciliations::ReconcileTransaction, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def make_transaction(amount: 100, purpose: 'purchase', combo: nil)
    PallasTrade::CommerceTransaction.create!(store: store, purpose: purpose, currency: 'USD',
                                             amount: amount, payment_combination: combo)
  end

  # 真实 captured payment：completed + capture_event + session（provider 锚点，completed→settled）
  def captured_payment(txn:, amount: 100, session_status: 'completed', order: nil)
    order ||= self.order
    pm = create(:bogus_payment_method, store: store, active: true)
    session = create(:bogus_payment_session, order: order, payment_method: pm, status: session_status,
                                             amount: amount, currency: 'USD', commerce_transaction: txn)
    payment = create(:payment, order: order, payment_method: pm, amount: amount,
                               state: 'completed', payment_session: session,
                               source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: amount.to_f)
    payment
  end

  # immutable journal entry（模拟已 posting——reconcile 消费方只读聚合，不经 Post 再造）
  def make_entry(txn:, entry_type:, amount:, payment: nil, split: nil, refund: nil)
    PallasTrade::FinancialLedgerEntry.create!(
      commerce_transaction: txn, entry_type: entry_type, amount: amount, currency: 'USD',
      idempotency_key: "spec-p47-#{entry_type}-#{txn.id}-#{SecureRandom.hex(6)}",
      effective_at: Time.current, payment: payment, payment_split: split, refund: refund
    )
  end

  def reconcile!(txn)
    described_class.call(transaction: txn)
  end

  it 'AC-4P7-03 single exact-paid purchase: journal cash == commercial → MATCHED' do
    txn = make_transaction
    payment = captured_payment(txn: txn, amount: 100)
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, payment: payment)

    result = reconcile!(txn)
    expect(result).to be_success
    expect(result.value).to be_matched
    expect(result.value.reasons).to eq([])
    summary = result.value.summary
    expect(summary.commercial_amount).to eq(100.0)
    expect(summary.cash_captured).to eq(100.0)
    expect(summary.gross_value_received).to eq(100.0)
    expect(summary.net_customer_value).to eq(100.0)
    expect(summary).not_to be_short_paid
    expect(result.value.provider_gross_amount).to eq(100.0)
    expect(result.value.source_reconciliations.size).to eq(1)
  end

  it 'AC-4P7-02 short payment: cash < commercial is exposed, NOT alarmed (AC-4016)' do
    txn = make_transaction(amount: 100)
    payment = captured_payment(txn: txn, amount: 80, session_status: 'completed')
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 80.0, payment: payment)

    result = reconcile!(txn)
    expect(result.value).to be_matched
    expect(result.value.reasons).to eq([]) # short-paid 不 alarm
    expect(result.value.summary).to be_short_paid
    expect(result.value.summary.cash_captured).to eq(80.0)
  end

  it 'AC-4P7-03 multi-payment: 2 captures → journal sums correctly (INV-04)' do
    txn = make_transaction(amount: 100)
    p1 = captured_payment(txn: txn, amount: 40)
    p2 = captured_payment(txn: txn, amount: 60)
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 40.0, payment: p1)
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 60.0, payment: p2)

    result = reconcile!(txn)
    expect(result.value).to be_matched
    expect(result.value.summary.cash_captured).to eq(100.0)
    expect(result.value.source_reconciliations.size).to eq(2)
  end

  it 'AC-4P7-04 partial refund: net reflects refund; refund kept per-entry (RV-F05)' do
    txn = make_transaction(amount: 100)
    payment = captured_payment(txn: txn, amount: 100)
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, payment: payment)
    refund = create(:refund, payment: payment, amount: 30, transaction_id: 're_p47_1')
    make_entry(txn: txn, entry_type: 'REFUND_SUCCEEDED', amount: 30.0, payment: payment, refund: refund)

    result = reconcile!(txn)
    expect(result.value).to be_matched
    summary = result.value.summary
    expect(summary.refund_total).to eq(30.0)
    expect(summary.net_customer_value).to eq(70.0)
    expect(summary.cash_captured).to eq(100.0)
  end

  it 'AC-4P7-05 journal posting missing: captured payment without CASH_CAPTURED entry → NEEDS_ATTENTION' do
    txn = make_transaction(amount: 100)
    captured_payment(txn: txn, amount: 100) # captured evidence, NO journal entry

    result = reconcile!(txn)
    expect(result.value).to be_needs_attention
    expect(result.value.reasons).to include('JOURNAL_POSTING_MISSING')
  end

  # bugfix C3 (FIN-P4 review 批1): reversed（有意冲销）的 CASH_CAPTURED 不得再报
  # JOURNAL_POSTING_MISSING —— 否则 sweep→repair 对同一被冲销 fact 无限空转。
  it 'bugfix C3: reversed CASH_CAPTURED entry is not flagged JOURNAL_POSTING_MISSING' do
    txn = make_transaction(amount: 100)
    payment = captured_payment(txn: txn, amount: 100)
    entry = make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, payment: payment)
    entry.mark_reversed! # Reverse 原语状态（append-only 冲销）

    result = reconcile!(txn)
    expect(result.value).not_to be_needs_attention
    expect(result.value.reasons).not_to include('JOURNAL_POSTING_MISSING')
  end

  it 'AC-4P7-06 allocation mismatch on a combination txn → MISMATCH + ALLOCATION_MISMATCH' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    txn = make_transaction(amount: 100, purpose: 'combined_payment', combo: combo)
    o1 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 60, total: 60,
                        payment_state: 'balance_due')
    o2 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 40, total: 40,
                        payment_state: 'balance_due')
    s1 = create(:payment_split, payment_combination: combo, order: o1, payment: nil, currency: 'USD',
                                captured_amount: 60)
    s2 = create(:payment_split, payment_combination: combo, order: o2, payment: nil, currency: 'USD',
                                captured_amount: 40)
    # 只 post 一个 split 的 allocation（60）→ allocation(60) != cash(100)
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 100.0)
    make_entry(txn: txn, entry_type: 'ORDER_ALLOCATION', amount: 60.0, split: s1)

    result = reconcile!(txn)
    expect(result.value).to be_mismatch
    expect(result.value.reasons).to include('ALLOCATION_MISMATCH')
  end

  it 'AC-4P7-01 combination exact-paid: cash == allocation == commercial → MATCHED' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    txn = make_transaction(amount: 100, purpose: 'combined_payment', combo: combo)
    o1 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 60, total: 60,
                        payment_state: 'balance_due')
    o2 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 40, total: 40,
                        payment_state: 'balance_due')
    s1 = create(:payment_split, payment_combination: combo, order: o1, payment: nil, currency: 'USD',
                                captured_amount: 60)
    s2 = create(:payment_split, payment_combination: combo, order: o2, payment: nil, currency: 'USD',
                                captured_amount: 40)
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 100.0)
    make_entry(txn: txn, entry_type: 'ORDER_ALLOCATION', amount: 60.0, split: s1)
    make_entry(txn: txn, entry_type: 'ORDER_ALLOCATION', amount: 40.0, split: s2)

    result = reconcile!(txn)
    expect(result.value).to be_matched
    summary = result.value.summary
    expect(summary.cash_captured).to eq(100.0)
    expect(summary.allocation_total).to eq(100.0)
    expect(summary.unallocated_amount).to eq(0.0)
    expect(result.value.reasons).to eq([])
  end

  it 'AC-4P7-07 legacy provider without contract on all sources → UNSUPPORTED (not MISMATCH)' do
    txn = make_transaction(amount: 100)
    pm = PallasTrade::PaymentMethod::ReconcileTransactionProbe.new(
      store: store, name: 'Legacy', type: 'PallasTrade::PaymentMethod::ReconcileTransactionProbe'
    )
    pm.save!
    session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'completed',
                                             amount: 100, currency: 'USD', commerce_transaction: txn)
    payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed',
                               payment_session: session, source: nil, skip_source_requirement: true)
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, payment: payment)

    result = reconcile!(txn)
    expect(result.value).to be_unsupported
    expect(result.value.reasons).to include('PROVIDER_CONTRACT_UNSUPPORTED')
  end

  it 'AC-4P7-07 no-PSP transaction (no payments, no journal activity) → NOT_APPLICABLE' do
    txn = make_transaction(amount: 100)

    result = reconcile!(txn)
    expect(result.value).to be_not_applicable
  end

  it 'AC-4P7-08 read-only: zero writes, zero state change, repeatable' do
    txn = make_transaction(amount: 100)
    payment = captured_payment(txn: txn, amount: 100)
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, payment: payment)
    entries_before = PallasTrade::FinancialLedgerEntry.count
    txn_state = txn.state

    first = reconcile!(txn)
    expect(first.value).to be_matched
    expect(txn.reload.state).to eq(txn_state)
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(entries_before)
    expect(reconcile!(txn).value.status).to eq(first.value.status)
  end

  it 'AC-4P7-10 nil transaction → failure' do
    expect(described_class.call(transaction: nil)).to be_failure
  end

  it 'AC-4P7-11 over-collect → MISMATCH + COMMERCIAL_AMOUNT_MISMATCH' do
    big_order = create(:order, store: store, state: 'pending', status: 'placed', item_total: 200, total: 200,
                               payment_state: 'balance_due')
    txn = make_transaction(amount: 100)
    payment = captured_payment(txn: txn, amount: 120, order: big_order)
    make_entry(txn: txn, entry_type: 'CASH_CAPTURED', amount: 120.0, payment: payment)

    result = reconcile!(txn)
    expect(result.value).to be_mismatch
    expect(result.value.reasons).to include('COMMERCIAL_AMOUNT_MISMATCH')
  end
end
