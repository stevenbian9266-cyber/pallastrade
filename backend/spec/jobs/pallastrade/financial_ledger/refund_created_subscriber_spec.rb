# frozen_string_literal: true

require 'rails_helper'

# PRD-20260906-payments-fin-p4-3 AC-4P3-10: refund.created → RefundCreatedSubscriber → PostRefund
RSpec.describe PallasTrade::FinancialLedger::RefundCreatedSubscriber, type: :job do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:subscriber) { described_class.new }

  def fire_created(refund)
    subscriber.send(:handle, double(payload: { 'id' => refund.prefixed_id }))
  end

  it 'declares subscription to refund.created' do
    expect(described_class.subscription_patterns).to include('refund.created')
  end

  it 'AC-4P3-10 posts a REFUND_SUCCEEDED entry when a successful refund fires refund.created' do
    txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100)
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                             amount: 100, currency: 'USD', commerce_transaction: txn)
    payment.update_column(:payment_session_id, session.id)
    refund = create(:refund, payment: payment, amount: 20, transaction_id: 're_sub_1')

    expect { fire_created(refund) }.to change(PallasTrade::FinancialLedgerEntry, :count).by(1)
    entry = PallasTrade::FinancialLedgerEntry.last
    expect(entry.entry_type).to eq('REFUND_SUCCEEDED')
    expect(entry.refund).to eq(refund)
    expect(entry.payment).to eq(payment)
    expect(entry.commerce_transaction).to eq(txn)

    # 重复触发 → 幂等不新增
    expect { fire_created(refund) }.not_to(change { PallasTrade::FinancialLedgerEntry.count })
  end

  it 'is a safe no-op for a refund without provable provider reference (AMBIGUOUS)' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', source: nil, skip_source_requirement: true)
    refund = create(:refund, payment: payment, amount: 10, transaction_id: 're_x')
    refund.update_column(:transaction_id, nil)

    expect { fire_created(refund) }.not_to raise_error
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'is a safe no-op for an unknown refund id / nil payload' do
    expect do
      subscriber.send(:handle, double(payload: { 'id' => 're_missing' }))
    end.not_to raise_error
    expect do
      subscriber.send(:handle, double(payload: nil))
    end.not_to raise_error
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end
end
