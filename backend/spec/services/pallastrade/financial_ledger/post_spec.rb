# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-2 AC-4P2-06/07/08/12/13
require 'rails_helper'

RSpec.describe PallasTrade::FinancialLedger::Post, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def make_transaction(amount: 100)
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: amount)
  end

  def make_payment(txn: nil)
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'completed')
    create(:payment_capture_event, payment: payment, amount: 100.0)
    payment
  end

  def cash_fact(txn:, payment: nil, status: 'CONFIRMED', fact_type: 'CASH_CAPTURED', amount: 100.0, currency: 'USD')
    PallasTrade::FinancialFact.new(
      fact_type: fact_type, status: status, amount: amount, currency: currency,
      instrument_class: 'PSP_CASH',
      commerce_transaction_id: txn&.prefixed_id,
      order_id: payment&.order&.prefixed_id,
      payment_id: payment&.prefixed_id,
      provider: payment&.payment_method&.type,
      provider_payment_reference: payment&.response_code,
      effective_at: Time.utc(2026, 9, 6, 0, 0, 0)
    )
  end

  def post!(fact, **opts)
    described_class.call(financial_fact: fact, **opts)
  end

  it 'AC-4P2-13/06 posts a CONFIRMED CASH_CAPTURED fact into the journal exactly once' do
    txn = make_transaction
    payment = make_payment(txn: txn)
    fact = cash_fact(txn: txn, payment: payment)

    result = post!(fact)
    expect(result).to be_success
    entry = result.value
    expect(entry).to be_a(PallasTrade::FinancialLedgerEntry)
    expect(entry.entry_type).to eq('CASH_CAPTURED')
    expect(entry.amount).to eq(100.0)
    expect(entry.currency).to eq('USD')
    expect(entry.commerce_transaction).to eq(txn)
    expect(entry.payment).to eq(payment)
    expect(entry.provider_reference).to eq(payment.response_code)
    expect(entry.idempotency_key).to eq(PallasTrade::FinancialLedgerEntry.fact_posting_key(fact))

    # 同一 fact 重复 post → 幂等返回同一 entry，不新增
    second = post!(fact)
    expect(second).to be_success
    expect(second.value.id).to eq(entry.id)
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(1)
  end

  it 'AC-4P2-06 pre-existing idempotency key returns the existing entry' do
    txn = make_transaction
    payment = make_payment(txn: txn)
    fact = cash_fact(txn: txn, payment: payment)
    first = post!(fact).value
    # 新 fact 对象 + 显式同 key（模拟 retry 携带原 key）
    fact2 = cash_fact(txn: txn, payment: payment)
    result = post!(fact2, idempotency_key: first.idempotency_key)
    expect(result).to be_success
    expect(result.value.id).to eq(first.id)
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(1)
  end

  it 'AC-4P2-07 concurrent duplicate insert is resolved by the unique constraint (no duplicate, no 500)' do
    txn = make_transaction
    payment = make_payment(txn: txn)
    fact = cash_fact(txn: txn, payment: payment)
    key = PallasTrade::FinancialLedgerEntry.fact_posting_key(fact)
    PallasTrade::FinancialLedgerEntry.create!(
      commerce_transaction: txn, entry_type: 'CASH_CAPTURED', amount: 100.0, currency: 'USD',
      idempotency_key: key, effective_at: Time.current
    )

    allow(PallasTrade::FinancialLedgerEntry).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
    result = post!(fact)
    expect(result).to be_success
    expect(result.value.idempotency_key).to eq(key)
    expect(PallasTrade::FinancialLedgerEntry.where(idempotency_key: key).count).to eq(1)
  end

  it 'AC-4P2-08 refuses AMBIGUOUS / UNSUPPORTED facts (no guess, no record)' do
    txn = make_transaction
    payment = make_payment(txn: txn)

    ambiguous = post!(cash_fact(txn: txn, payment: payment, status: 'AMBIGUOUS'))
    expect(ambiguous).to be_failure
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)

    unsupported = post!(cash_fact(txn: txn, payment: payment, status: 'UNSUPPORTED'))
    expect(unsupported).to be_failure
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-4P2-08/AC-4P4-03 refuses non-activated entry types (PSP_FEE — FIN-P4-5 reserved)' do
    txn = make_transaction
    payment = make_payment(txn: txn)
    result = post!(cash_fact(txn: txn, payment: payment, fact_type: 'PSP_FEE'))
    expect(result).to be_failure
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-4P2-08 refuses a fact without resolvable commerce transaction' do
    payment = make_payment
    result = post!(cash_fact(txn: nil, payment: payment))
    expect(result).to be_failure
    # 不存在的 prefixed txn
    ghost = cash_fact(txn: nil, payment: payment).to_h
    ghost_fact = PallasTrade::FinancialFact.new(**ghost.merge(commerce_transaction_id: 'txn_ghost_does_not_exist'))
    expect(post!(ghost_fact)).to be_failure
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-4P2-12 posting is read-only with respect to payment/session state (no side effects)' do
    txn = make_transaction
    payment = make_payment(txn: txn)
    before_state = payment.state

    expect(payment).not_to receive(:save)
    expect(payment).not_to receive(:complete!)
    post!(cash_fact(txn: txn, payment: payment))
    expect(payment.reload.state).to eq(before_state)
  end
end
