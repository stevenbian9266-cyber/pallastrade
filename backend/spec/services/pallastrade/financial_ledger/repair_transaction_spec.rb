# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-8 AC-4P8-01/02/03/08
require 'rails_helper'

RSpec.describe PallasTrade::FinancialLedger::RepairTransaction, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def make_transaction(amount: 100, purpose: 'purchase', combo: nil)
    PallasTrade::CommerceTransaction.create!(store: store, purpose: purpose, currency: 'USD',
                                             amount: amount, payment_combination: combo)
  end

  # captured payment（真实证据：completed + capture_event + session）
  def captured_payment(txn:, amount: 100)
    pm = create(:bogus_payment_method, store: store, active: true)
    session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'completed',
                                             amount: amount, currency: 'USD', commerce_transaction: txn)
    payment = create(:payment, order: order, payment_method: pm, amount: amount,
                               state: 'completed', payment_session: session,
                               source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: amount.to_f)
    payment
  end

  def repair!(txn)
    described_class.call(transaction: txn)
  end

  it 'AC-4P8-01 repairs a missing CASH_CAPTURED entry for a captured payment (no re-payment/charge)' do
    txn = make_transaction
    payment = captured_payment(txn: txn, amount: 100)

    result = repair!(txn)
    expect(result).to be_success
    expect(result.value[:repaired].size).to eq(1)
    entry = result.value[:repaired].first
    expect(entry).to be_a(PallasTrade::FinancialLedgerEntry)
    expect(entry.entry_type).to eq('CASH_CAPTURED')
    expect(entry.commerce_transaction).to eq(txn)
    expect(entry.payment).to eq(payment)

    # 未创建/未改 payment；未 charge
    expect(payment.reload.state).to eq('completed')
    expect(PallasTrade::Payment.count).to eq(1)
  end

  it 'AC-4P8-03 repair is idempotent: second run finds nothing to repair' do
    txn = make_transaction
    captured_payment(txn: txn, amount: 100)

    first = repair!(txn)
    expect(first.value[:repaired].size).to eq(1)
    second = repair!(txn)
    expect(second.value[:repaired]).to eq([])
    expect(second.value[:already_present].size).to eq(1)
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(1)
  end

  # bugfix C3 (FIN-P4 review 批1): 已被 Reverse 冲销的 fact 不得被 repair 再补记——
  # reversed 条目保留原 idempotency_key，若仍按 active 判定缺失会无限 no-op repair。
  it 'bugfix C3: a reversed CASH_CAPTURED entry is NOT re-repaired (terminates no-op loop)' do
    txn = make_transaction
    payment = captured_payment(txn: txn, amount: 100)
    entry = PallasTrade::FinancialLedgerEntry.create!(
      commerce_transaction: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, currency: 'USD',
      idempotency_key: "spec-c3-#{SecureRandom.hex(6)}", effective_at: Time.current, payment: payment
    )
    entry.mark_reversed!

    result = repair!(txn)
    expect(result).to be_success
    expect(result.value[:repaired]).to eq([])
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(1)
  end

  it 'AC-4P8-02 repairs a missing REFUND_SUCCEEDED entry for a succeeded refund' do
    txn = make_transaction
    payment = captured_payment(txn: txn, amount: 100)
    # 先补 cash entry，再建 refund（带 provider reference = succeeded）
    repair!(txn)
    create(:refund, payment: payment, amount: 30, transaction_id: 're_repair_1')

    result = repair!(txn)
    refund_entries = result.value[:repaired].select { |e| e.entry_type == 'REFUND_SUCCEEDED' }
    expect(refund_entries.size).to eq(1)
    expect(refund_entries.first.refund.transaction_id).to eq('re_repair_1')
    expect(refund_entries.first.amount).to eq(30.0)
  end

  it 'AC-4P8-03 a refund without provider reference is NOT repaired (no guess)' do
    txn = make_transaction
    payment = captured_payment(txn: txn, amount: 100)
    repair!(txn)
    refund = create(:refund, payment: payment, amount: 30)
    refund.update_column(:transaction_id, nil) # 无 provider reference → 不可证明

    result = repair!(txn)
    expect(result.value[:repaired]).to eq([])
    expect(result.value[:skipped].any? { |s| s[:source_type] == :refund }).to be false
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'REFUND_SUCCEEDED').count).to eq(0)
  end

  it 'AC-4P8-02/08 combination settled splits → repairs missing ORDER_ALLOCATION entries (no splits mutation)' do
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

    result = repair!(txn)
    allocations = result.value[:repaired].select { |e| e.entry_type == 'ORDER_ALLOCATION' }
    expect(allocations.size).to eq(2)
    expect(allocations.map(&:payment_split_id).sort).to eq([s1.id, s2.id].sort)

    expect(s1.reload.captured_amount).to eq(60.0)
    expect(s2.reload.captured_amount).to eq(40.0)
    expect(combo.reload.status).to eq('succeeded')
  end

  it 'AC-4P8-03 already-present entries are untouched on a combination' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    txn = make_transaction(amount: 100, purpose: 'combined_payment', combo: combo)
    o1 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                        payment_state: 'balance_due')
    s1 = create(:payment_split, payment_combination: combo, order: o1, payment: nil, currency: 'USD',
                                captured_amount: 100)
    repair!(txn)
    before = PallasTrade::FinancialLedgerEntry.count

    second = repair!(txn)
    expect(second.value[:repaired]).to eq([])
    expect(second.value[:already_present].size).to be >= 1
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(before)
  end

  it 'AC-4P8-08 read-only boundary: no new Payment/Refund/state change, repeatable' do
    txn = make_transaction
    payment = captured_payment(txn: txn, amount: 100)
    payments_before = PallasTrade::Payment.count
    refunds_before = PallasTrade::Refund.count

    repair!(txn)
    expect(PallasTrade::Payment.count).to eq(payments_before)
    expect(PallasTrade::Refund.count).to eq(refunds_before)
    expect(payment.reload.state).to eq('completed')
    expect(txn.reload.state).to eq(txn.state)
    expect(repair!(txn).value[:repaired]).to eq([])
  end

  it 'AC-4P8-08 nil transaction → failure' do
    expect(described_class.call(transaction: nil)).to be_failure
  end
end
