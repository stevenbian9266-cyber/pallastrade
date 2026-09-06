# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-4 AC-4P4-02/03/04/05/07
require 'rails_helper'

RSpec.describe PallasTrade::FinancialLedger::AllocationIntegrity, type: :service do
  let(:store) { @default_store }

  def make_combination(amount: 100, txn: true)
    combo = create(:payment_combination, store: store, currency: 'USD', amount: amount, status: 'succeeded',
                                         completed_at: Time.current)
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

  def add_captured_split(combo:, captured:)
    order = make_order(captured)
    create(:payment_split, payment_combination: combo, order: order, payment: nil,
                           currency: 'USD', captured_amount: captured)
  end

  # 真实 posting 路径：逐 split PostAllocation
  def post_all!(combo)
    combo.payment_splits.each do |split|
      PallasTrade::FinancialLedger::PostAllocation.call(split: split)
    end
  end

  def integrity!(combo)
    described_class.call(combination: combo).value
  end

  it 'AC-4P4-02 balanced after posting allocations for all captured splits' do
    combo = make_combination(amount: 100)
    add_captured_split(combo: combo, captured: 60)
    add_captured_split(combo: combo, captured: 40)
    post_all!(combo)

    result = integrity!(combo)
    expect(result[:split_captured_total]).to eq(100.0)
    expect(result[:allocation_total]).to eq(100.0)
    expect(result[:balanced?]).to be(true)
  end

  it 'AC-4P4-02 unbalanced when an allocation is missing (integrity surfaces the gap)' do
    combo = make_combination(amount: 100)
    add_captured_split(combo: combo, captured: 60)
    add_captured_split(combo: combo, captured: 40)
    post_all!(combo)

    # 多一个已 captured split 但未 post（模拟 posting 丢失/漏接）
    add_captured_split(combo: combo, captured: 25)
    result = integrity!(combo)
    expect(result[:split_captured_total]).to eq(125.0)
    expect(result[:allocation_total]).to eq(100.0)
    expect(result[:balanced?]).to be(false)
  end

  it 'AC-4P4-03 ORDER_ALLOCATION never inflates cash aggregation (typed isolation)' do
    combo = make_combination(amount: 100)
    add_captured_split(combo: combo, captured: 60)
    post_all!(combo)

    # 同一 txn 上另有一条真实 cash capture（对比）
    txn = combo.commerce_transaction
    payment = create(:payment, amount: 60, state: 'completed', source: nil,
                               skip_source_requirement: true, payment_combination: combo)
    create(:payment_capture_event, payment: payment, amount: 60.0)
    PallasTrade::FinancialFact.new(
      fact_type: 'CASH_CAPTURED', status: 'CONFIRMED', amount: 60.0, currency: 'USD',
      instrument_class: 'PSP_CASH', commerce_transaction_id: txn.prefixed_id,
      payment_id: payment.prefixed_id
    ).tap { |f| PallasTrade::FinancialLedger::Post.call(financial_fact: f) }

    cash_sum = PallasTrade::FinancialLedgerEntry.active
                                                 .where(commerce_transaction_id: txn.id)
                                                 .where(entry_type: %w[CASH_CAPTURED STORE_CREDIT_APPLIED
                                                                       OFFLINE_PAYMENT_RECORDED REFUND_SUCCEEDED])
                                                 .sum(:amount)
    # cash 聚合只含 CASH_CAPTURED 60；ORDER_ALLOCATION 60 不计入（AC-4013）
    expect(cash_sum.to_d).to eq(60.0)
    allocation_sum = PallasTrade::FinancialLedgerEntry.active
                                                       .where(commerce_transaction_id: txn.id)
                                                       .where(entry_type: 'ORDER_ALLOCATION')
                                                       .sum(:amount)
    expect(allocation_sum.to_d).to eq(60.0)
  end

  it 'AC-4P4-04 exact-paid combination → allocation_total == captured_total == combination.amount' do
    combo = make_combination(amount: 100)
    add_captured_split(combo: combo, captured: 60)
    add_captured_split(combo: combo, captured: 40)
    post_all!(combo)

    result = integrity!(combo)
    expect(result[:allocation_total]).to eq(result[:split_captured_total])
    expect(result[:allocation_total]).to eq(combo.amount.to_d)
    expect(result[:balanced?]).to be(true)
  end

  it 'AC-4P4-05 short payment (captured < commercial) → allocation reflects actual captured, balanced' do
    combo = make_combination(amount: 100) # commercial 100
    add_captured_split(combo: combo, captured: 30)
    add_captured_split(combo: combo, captured: 20)
    post_all!(combo)

    result = integrity!(combo)
    expect(result[:split_captured_total]).to eq(50.0)
    expect(result[:allocation_total]).to eq(50.0)
    expect(result[:balanced?]).to be(true)
    expect(combo.amount.to_d).to eq(100.0) # 组合商业额不变（short payment 是真实状态，非 ledger error）
  end

  it 'AC-4P4-07 reversal: original excluded from active set; without re-post → balanced? false (gap surfaced)' do
    combo = make_combination(amount: 100)
    s1 = add_captured_split(combo: combo, captured: 60)
    add_captured_split(combo: combo, captured: 40)
    post_all!(combo)
    expect(integrity!(combo)[:balanced?]).to be(true)

    entry = PallasTrade::FinancialLedgerEntry.active
                                             .where(entry_type: 'ORDER_ALLOCATION', payment_split_id: s1.id).first!
    reversal = PallasTrade::FinancialLedger::Reverse.call(entry: entry)
    expect(reversal).to be_success
    expect(entry.reload).to be_reversed

    # active 集合：原 entry 排除、reversal（-60）计入 → 恒等式如实报不一致（未补记）
    result = integrity!(combo)
    expect(result[:allocation_total]).to eq(40.0 - 60.0)
    expect(result[:balanced?]).to be(false)
    expect(PallasTrade::FinancialLedgerEntry.active.where(entry_type: 'ORDER_ALLOCATION').count).to eq(2)
  end

  it 'nil combination → failure' do
    result = described_class.call(combination: nil)
    expect(result).to be_failure
  end
end
