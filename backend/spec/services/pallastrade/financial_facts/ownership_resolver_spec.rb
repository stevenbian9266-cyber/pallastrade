# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-1 AC-4P1-14/15/16/17
require 'rails_helper'

RSpec.describe PallasTrade::FinancialFacts::OwnershipResolver, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def make_transaction(purpose: 'purchase', amount: 100)
    PallasTrade::CommerceTransaction.create!(store: store, purpose: purpose, currency: 'USD', amount: amount)
  end

  it 'AC-4P1-14 resolves ownership via Payment → PaymentSession → CommerceTransaction' do
    txn = make_transaction
    session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                             amount: 100, currency: 'USD', commerce_transaction: txn)
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', payment_session: session)

    result = described_class.call(payment: payment)
    expect(result).to be_success
    expect(result.value[:transaction]).to eq(txn)
    expect(result.value[:path]).to eq(:payment_session)
  end

  it 'AC-4P1-15 resolves ownership via Payment → PaymentCombination → CommerceTransaction' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    txn = make_transaction(purpose: 'combined_payment')
    txn.update!(payment_combination: combo)
    payment = create(:payment, payment_method: payment_method, amount: 100, state: 'completed',
                               order: nil, payment_combination: combo, source: nil,
                               skip_source_requirement: true)

    result = described_class.call(payment: payment)
    expect(result).to be_success
    expect(result.value[:transaction]).to eq(txn)
    expect(result.value[:path]).to eq(:payment_combination)
  end

  it 'AC-4P1-17 no reliable path → transaction nil, no fabricated ownership' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'completed')

    result = described_class.call(payment: payment)
    expect(result).to be_success
    expect(result.value[:transaction]).to be_nil
    expect(result.value[:path]).to eq(:none)
  end

  it 'AC-4P1-14/17 explicit transaction context takes precedence' do
    txn = make_transaction
    # payment with no natural ownership
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'completed')

    result = described_class.call(payment: payment, explicit_transaction: txn)
    expect(result.value[:transaction]).to eq(txn)
    expect(result.value[:path]).to eq(:explicit)
  end

  it 'AC-4P1-16 PSP reference alone never resolves ownership' do
    # payment carries a pi_-style response_code but has no session/combination link
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: 'pi_test_ref')

    result = described_class.call(payment: payment)
    expect(result.value[:transaction]).to be_nil
    expect(result.value[:path]).to eq(:none)
  end

  it 'AC-4P1-18/29 resolves refund ownership through its payment' do
    txn = make_transaction
    session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                             amount: 100, currency: 'USD', commerce_transaction: txn)
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', payment_session: session)
    refund = create(:refund, payment: payment, amount: 10, transaction_id: 're_test')

    result = described_class.call(refund: refund)
    expect(result).to be_success
    expect(result.value[:transaction]).to eq(txn)
    expect(result.value[:path]).to eq(:payment_session)
  end

  it 'refund without payment → no_payment path' do
    refund = build(:refund, payment: nil, amount: 10, transaction_id: 're_x')
    result = described_class.call(refund: refund)
    expect(result).to be_success
    expect(result.value[:path]).to eq(:no_payment)
  end
end
