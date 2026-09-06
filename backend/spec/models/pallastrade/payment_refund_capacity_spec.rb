# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-1 AC-R61-07/08/09/10 —— Refund Capacity（active 占用 / failed 释放 / 并发不超付）
RSpec.describe PallasTrade::Payment, type: :model do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  it 'refundable_capacity = amount − succeeded − active(requested/processing/ambiguous)' do
    expect(payment.refundable_capacity).to eq(100)

    create(:refund, payment: payment, amount: 30, transaction_id: 're_ok') # succeeded
    expect(payment.refundable_capacity).to eq(70)

    create(:refund, payment: payment, amount: 20, transaction_id: nil, state: 'requested') # active
    expect(payment.refundable_capacity).to eq(50)
  end

  it 'failed/canceled refunds do NOT consume capacity (AC-6009)' do
    create(:refund, payment: payment, amount: 60, transaction_id: nil, state: 'failed')
    create(:refund, payment: payment, amount: 10, transaction_id: nil, state: 'canceled')
    expect(payment.refundable_capacity).to eq(100)
  end

  it 'credit_allowed alias keeps legacy callers working' do
    expect(payment.credit_allowed).to eq(payment.refundable_capacity)
    create(:refund, payment: payment, amount: 40, transaction_id: 're_ok')
    expect(payment.credit_allowed).to eq(60)
  end

  it 'multiple successful partial refunds supported (AC-6010); each reduces capacity' do
    create(:refund, payment: payment, amount: 10, transaction_id: 're_1')
    create(:refund, payment: payment, amount: 20, transaction_id: 're_2')
    expect(payment.refundable_capacity).to eq(70)
  end

  it 'refund create validation rejects amount over capacity (concurrent in-flight honored)' do
    create(:refund, payment: payment, amount: 80, transaction_id: nil, state: 'processing')
    refund = build(:refund, payment: payment, amount: 30, transaction_id: nil, state: 'requested')
    expect(refund).not_to be_valid
    expect(refund.errors[:amount].join).to include('greater than the allowed amount')
  end
end
