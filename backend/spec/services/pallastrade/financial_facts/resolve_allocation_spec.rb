# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-4 AC-4P4-01/08
require 'rails_helper'

RSpec.describe PallasTrade::FinancialFacts::ResolveAllocation, type: :service do
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

  def make_split(combo:, order:, captured:, payment: nil)
    create(:payment_split, payment_combination: combo, order: order, payment: payment,
                           currency: 'USD', captured_amount: captured)
  end

  def resolve!(split)
    described_class.call(split: split)
  end

  it 'AC-4P4-01 resolves a captured split under a txn-ized combination → CONFIRMED ORDER_ALLOCATION' do
    combo = make_combination
    order = make_order(60)
    payment = create(:payment, amount: 60, state: 'completed', source: nil,
                               skip_source_requirement: true, payment_combination: combo)
    split = make_split(combo: combo, order: order, captured: 60, payment: payment)

    fact = resolve!(split).value
    expect(fact.fact_type).to eq(PallasTrade::FinancialFact::ORDER_ALLOCATION)
    expect(fact.status).to eq(PallasTrade::FinancialFact::CONFIRMED)
    expect(fact.amount).to eq(60.0)
    expect(fact.currency).to eq('USD')
    expect(fact.order_id).to eq(order.prefixed_id)
    expect(fact.payment_split_id).to eq(split.prefixed_id)
    expect(fact.payment_combination_id).to eq(combo.prefixed_id)
    expect(fact.commerce_transaction_id).to eq(combo.commerce_transaction.prefixed_id)
    expect(fact).to be_allocation
  end

  it 'AC-4P4-08 split without combination → AMBIGUOUS (no guess), reason split_without_combination' do
    order = make_order(60)
    split = create(:payment_split, payment_combination: nil, order: order, payment: nil,
                                   currency: 'USD', captured_amount: 60)

    fact = resolve!(split).value
    expect(fact.status).to eq(PallasTrade::FinancialFact::AMBIGUOUS)
    expect(fact.reason_code).to eq('split_without_combination')
    expect(fact.commerce_transaction_id).to be_nil
  end

  it 'AC-4P4-08 legacy combination without commerce transaction → AMBIGUOUS' do
    combo = make_combination(txn: false)
    order = make_order(60)
    split = make_split(combo: combo, order: order, captured: 60)

    fact = resolve!(split).value
    expect(fact.status).to eq(PallasTrade::FinancialFact::AMBIGUOUS)
    expect(fact.reason_code).to eq('combination_without_commerce_transaction')
    expect(fact.commerce_transaction_id).to be_nil
  end

  it 'AC-4P4-08 split with captured_amount 0 → AMBIGUOUS (reason split_not_captured)' do
    combo = make_combination
    order = make_order(60)
    split = make_split(combo: combo, order: order, captured: 0)

    fact = resolve!(split).value
    expect(fact.status).to eq(PallasTrade::FinancialFact::AMBIGUOUS)
    expect(fact.reason_code).to eq('split_not_captured')
    expect(fact.commerce_transaction_id).to be_nil
  end

  it 'AC-4P4-09 resolution is read-only for split/combination/order' do
    combo = make_combination
    order = make_order(60)
    split = make_split(combo: combo, order: order, captured: 60)
    split_captured = split.captured_amount

    expect(split).not_to receive(:save)
    expect(split).not_to receive(:update)
    expect(combo).not_to receive(:succeed!)

    fact = resolve!(split).value
    expect(fact).to be_present
    expect(split.reload.captured_amount).to eq(split_captured)
    expect(combo.reload.status).to eq('pending')
  end

  it 'nil split → failure' do
    result = described_class.call(split: nil)
    expect(result).to be_failure
  end
end
