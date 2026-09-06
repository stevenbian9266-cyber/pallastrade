# frozen_string_literal: true

require 'rails_helper'

# REV-P6-1 (PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation):
# refund.succeeded → RefundSucceededSubscriber → PostRefund。
# （原 FIN-P4-3 AC-4P3-10 refund.created 接线在 REV-P6-1 后迁移：Refund 创建 = durable REQUESTED，
#   不再隐含 provider 成功；posting 仅在 state 迁移到 succeeded 后触发。）
RSpec.describe PallasTrade::FinancialLedger::RefundSucceededSubscriber, type: :job do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:subscriber) { described_class.new }

  def fire_succeeded(refund)
    subscriber.send(:handle, double(payload: { 'id' => refund.prefixed_id }))
  end

  def completed_payment
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)
    payment
  end

  it 'declares subscription to refund.succeeded' do
    expect(described_class.subscription_patterns).to include('refund.succeeded')
  end

  it 'posts a REFUND_SUCCEEDED entry when a succeeded refund fires refund.succeeded' do
    txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100)
    payment = completed_payment
    session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                             amount: 100, currency: 'USD', commerce_transaction: txn)
    payment.update_column(:payment_session_id, session.id)
    refund = create(:refund, payment: payment, amount: 20, transaction_id: 're_sub_1') # factory 默认 succeeded

    expect { fire_succeeded(refund) }.to change(PallasTrade::FinancialLedgerEntry, :count).by(1)
    entry = PallasTrade::FinancialLedgerEntry.last
    expect(entry.entry_type).to eq('REFUND_SUCCEEDED')
    expect(entry.refund).to eq(refund)
    expect(entry.payment).to eq(payment)
    expect(entry.commerce_transaction).to eq(txn)

    # 重复触发 → 幂等不新增
    expect { fire_succeeded(refund) }.not_to(change { PallasTrade::FinancialLedgerEntry.count })
  end

  it 'does NOT post for non-succeeded refunds (requested/processing/ambiguous/failed)' do
    payment = completed_payment
    %w[requested processing ambiguous failed].each do |state|
      refund = create(:refund, payment: payment, amount: 10, transaction_id: nil, state: state)
      expect { fire_succeeded(refund) }.not_to raise_error
    end

    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'is a safe no-op for a succeeded refund without provable provider reference (AMBIGUOUS)' do
    payment = completed_payment
    refund = create(:refund, payment: payment, amount: 10, transaction_id: 're_x')
    refund.update_column(:transaction_id, nil)

    expect { fire_succeeded(refund) }.not_to raise_error
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
