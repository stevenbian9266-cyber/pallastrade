# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-1 AC-4P1-18/19/20/23
require 'rails_helper'

RSpec.describe PallasTrade::FinancialFacts::ResolveRefund, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def captured_payment(amount: 100, session: nil, combo: nil)
    create(:payment, order: (combo ? nil : order), payment_method: payment_method, amount: amount,
                     state: 'completed', payment_session: session, payment_combination: combo,
                     source: nil, skip_source_requirement: true)
  end

  def resolve!(refund, transaction: nil)
    described_class.call(refund: refund, transaction: transaction)
  end

  it 'AC-4P1-18 successful refund → single REFUND_SUCCEEDED fact with provider reference' do
    payment = captured_payment
    create(:payment_capture_event, payment: payment, amount: 100.0)
    refund = create(:refund, payment: payment, amount: 20, transaction_id: 're_stripe_1')

    fact = resolve!(refund).value
    expect(fact.fact_type).to eq(PallasTrade::FinancialFact::REFUND_SUCCEEDED)
    expect(fact.status).to eq(PallasTrade::FinancialFact::CONFIRMED)
    expect(fact.amount).to eq(20.0)
    expect(fact.currency).to eq('USD')
    expect(fact.refund_id).to eq(refund.prefixed_id)
    expect(fact.payment_id).to eq(payment.prefixed_id)
    expect(fact.provider_refund_reference).to eq('re_stripe_1')
  end

  it 'AC-4P1-19 multiple partial refunds → independent facts (never aggregated)' do
    payment = captured_payment
    create(:payment_capture_event, payment: payment, amount: 100.0)
    r1 = create(:refund, payment: payment, amount: 20, transaction_id: 're_a')
    r2 = create(:refund, payment: payment, amount: 10, transaction_id: 're_b')

    f1 = resolve!(r1).value
    f2 = resolve!(r2).value
    expect(f1.amount).to eq(20.0)
    expect(f2.amount).to eq(10.0)
    expect(f1.refund_id).not_to eq(f2.refund_id)
    expect(f1.provider_refund_reference).to eq('re_a')
    expect(f2.provider_refund_reference).to eq('re_b')
  end

  it 'AC-4P1-20 combination target refund → exactly one fact (splits/participants never duplicate it)' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    payment = captured_payment(combo: combo)
    # 两个成员订单的 splits 存在（alocation evidence）——不得让 refund 复制成多个退款事实
    o1 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 60, total: 60)
    o2 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 40, total: 40)
    create(:payment_split, payment_combination: combo, order: o1, payment: payment, currency: 'USD', captured_amount: 60)
    create(:payment_split, payment_combination: combo, order: o2, payment: payment, currency: 'USD', captured_amount: 40)

    refund = create(:refund, payment: payment, amount: 20, transaction_id: 're_combo_1')
    fact = resolve!(refund).value

    expect(fact.fact_type).to eq(PallasTrade::FinancialFact::REFUND_SUCCEEDED)
    expect(fact.refund_id).to eq(refund.prefixed_id)
    expect(fact.amount).to eq(20.0)
    expect(fact.payment_combination_id).to eq(combo.prefixed_id)
    expect(fact.evidence).not_to include(:duplicated_across_participants)
  end

  it 'AC-4P1-18 refund ownership resolves through payment session' do
    txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                             amount: 100, currency: 'USD', commerce_transaction: txn)
    payment = captured_payment(session: session)
    refund = create(:refund, payment: payment, amount: 10, transaction_id: 're_owned')

    fact = resolve!(refund).value
    expect(fact.commerce_transaction_id).to eq(txn.prefixed_id)
  end

  it 'AC-4P1-27 refund without provable provider reference → AMBIGUOUS, no REFUND_SUCCEEDED guess' do
    payment = captured_payment
    refund = create(:refund, payment: payment, amount: 10, transaction_id: 're_tmp')
    refund.update_column(:transaction_id, nil) # 模拟历史/手工记录缺 provider ref

    fact = resolve!(refund).value
    expect(fact.fact_type).to eq(PallasTrade::FinancialFact::NONE)
    expect(fact.status).to eq(PallasTrade::FinancialFact::AMBIGUOUS)
    expect(fact.reason_code).to eq('refund_success_not_provable')
  end

  it 'AC-4P1-23 resolution is read-only for refund rows' do
    payment = captured_payment
    refund = create(:refund, payment: payment, amount: 10, transaction_id: 're_ro')

    expect(refund).not_to receive(:save)
    expect(refund).not_to receive(:update)
    fact = resolve!(refund).value
    expect(fact).to be_present
    expect(refund.reload.transaction_id).to eq('re_ro')
  end
end
