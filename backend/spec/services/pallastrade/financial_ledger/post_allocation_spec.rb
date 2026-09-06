# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-4 AC-4P4-01/05/06/08/09
require 'rails_helper'

RSpec.describe PallasTrade::FinancialLedger::PostAllocation, type: :service do
  let(:store) { @default_store }

  def make_combination(amount: 100, txn: true)
    combo = create(:payment_combination, store: store, currency: 'USD', amount: amount, status: 'pending')
    if txn
      PallasTrade::CommerceTransaction.create!(store: store, purpose: 'combined_payment', currency: 'USD',
                                               amount: amount, payment_combination: combo)
    end
    combo
  end

  def make_order(total)
    create(:order, store: store, state: 'pending', status: 'placed', item_total: total, total: total,
                   payment_state: 'balance_due')
  end

  def captured_split(combo:, captured:, order_total: nil)
    order = make_order(order_total || captured)
    create(:payment_split, payment_combination: combo, order: order, payment: nil,
                           currency: 'USD', captured_amount: captured)
  end

  def post!(split)
    described_class.call(split: split)
  end

  it 'AC-4P4-01 posts exactly one ORDER_ALLOCATION entry for a captured split' do
    combo = make_combination
    split = captured_split(combo: combo, captured: 60, order_total: 60)

    result = post!(split)
    expect(result).to be_success
    payload = result.value
    expect(payload[:skipped]).to be(false)
    entry = payload[:entry]
    expect(entry).to be_a(PallasTrade::FinancialLedgerEntry)
    expect(entry.entry_type).to eq('ORDER_ALLOCATION')
    expect(entry.amount).to eq(60.0)
    expect(entry.currency).to eq('USD')
    expect(entry.order).to eq(split.order)
    expect(entry.payment_split).to eq(split)
    expect(entry.payment_combination).to eq(combo)
    expect(entry.commerce_transaction).to eq(combo.commerce_transaction)
    expect(entry.idempotency_key).to eq("fact:ORDER_ALLOCATION:#{combo.commerce_transaction.prefixed_id}:#{split.prefixed_id}")
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'ORDER_ALLOCATION').count).to eq(1)
  end

  it 'AC-4P4-05/06 idempotent across replays/retries (stable key, no timestamp component)' do
    combo = make_combination
    split = captured_split(combo: combo, captured: 60, order_total: 60)

    first = post!(split).value[:entry]
    # 幂等 key 显式稳定（fact:ORDER_ALLOCATION:txn:split）——不含 effective_at 时刻，重放/重试安全
    expect(first.idempotency_key).to eq("fact:ORDER_ALLOCATION:#{combo.commerce_transaction.prefixed_id}:#{split.prefixed_id}")
    expect(first.idempotency_key).not_to match(/:\d{8,}$/)

    # 再次触发 → 命中同一条
    second = post!(split).value[:entry]
    expect(second.id).to eq(first.id)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'ORDER_ALLOCATION').count).to eq(1)
  end

  it 'AC-4P4-08 skip: split without resolvable transaction → no entry (reason preserved)' do
    combo = make_combination(txn: false) # legacy no txn
    split = captured_split(combo: combo, captured: 60, order_total: 60)

    result = post!(split)
    expect(result).to be_success
    expect(result.value[:skipped]).to be(true)
    expect(result.value[:entry]).to be_nil
    expect(result.value[:reason]).to eq('combination_without_commerce_transaction')
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'ORDER_ALLOCATION').count).to eq(0)
  end

  it 'AC-4P4-08 skip: split without combination → no entry' do
    order = make_order(60)
    split = create(:payment_split, payment_combination: nil, order: order, payment: nil,
                                   currency: 'USD', captured_amount: 60)

    result = post!(split)
    expect(result).to be_success
    expect(result.value[:skipped]).to be(true)
    expect(result.value[:reason]).to eq('split_without_combination')
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-4P4-09 posting is read-only for split/combination (no state change, no new records besides the entry)' do
    combo = make_combination
    split = captured_split(combo: combo, captured: 60, order_total: 60)
    before_captured = split.captured_amount
    combos_before = PallasTrade::PaymentCombination.count
    splits_before = PallasTrade::PaymentSplit.count

    result = post!(split)
    expect(result).to be_success
    expect(result.value[:skipped]).to be(false)
    expect(split.reload.captured_amount).to eq(before_captured)
    expect(combo.reload.status).to eq('pending')
    expect(PallasTrade::PaymentCombination.count).to eq(combos_before)
    expect(PallasTrade::PaymentSplit.count).to eq(splits_before)
  end

  it 'nil split → failure' do
    result = described_class.call(split: nil)
    expect(result).to be_failure
  end
end
