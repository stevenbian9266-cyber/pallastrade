# frozen_string_literal: true

require 'rails_helper'

# PRD-20260906-payments-fin-p4-3 AC-4P3-10: payment.paid → PaymentPaidSubscriber → PostPayment
# 事件在测试环境经 Sidekiq 异步执行 → 与 payment_session_reservation_subscriber_spec 一致，直接驱动 handler。
RSpec.describe PallasTrade::FinancialLedger::PaymentPaidSubscriber, type: :job do
  let(:store) { @default_store }
  let(:subscriber) { described_class.new }

  def fire_paid(payment)
    subscriber.send(:handle, double(payload: { 'id' => payment.prefixed_id }))
  end

  it 'declares subscription to payment.paid' do
    expect(described_class.subscription_patterns).to include('payment.paid')
  end

  it 'AC-4P3-10 posts a CASH_CAPTURED entry when a captured payment fires payment.paid' do
    pm = create(:bogus_payment_method, store: store, active: true, auto_capture: true)
    order = create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                           payment_state: 'balance_due')
    txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100)
    session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'pending',
                                             amount: 100, currency: 'USD', commerce_transaction: txn)
    payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'checkout',
                               payment_session: session)
    payment.confirm! # real capture path → completed
    expect(payment).to be_completed

    expect { fire_paid(payment) }.to change(PallasTrade::FinancialLedgerEntry, :count).by(1)
    entry = PallasTrade::FinancialLedgerEntry.last
    expect(entry.entry_type).to eq('CASH_CAPTURED')
    expect(entry.payment).to eq(payment)
    expect(entry.commerce_transaction).to eq(txn)

    # 重复触发 → 幂等不新增
    expect { fire_paid(payment) }.not_to(change { PallasTrade::FinancialLedgerEntry.count })
  end

  it 'AC-4P3-10 skip (AMBIGUOUS) is a safe no-op, no entry, no raise' do
    pm = create(:bogus_payment_method, store: store, active: true, auto_capture: true)
    order = create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                           payment_state: 'balance_due')
    payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed')
    # no capture event → ResolvePayment → AMBIGUOUS

    expect do
      fire_paid(payment)
    end.not_to raise_error
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'is a safe no-op for an unknown payment id' do
    expect do
      subscriber.send(:handle, double(payload: { 'id' => 'py_missing' }))
    end.not_to raise_error
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'is a safe no-op for a nil payload' do
    expect do
      subscriber.send(:handle, double(payload: nil))
    end.not_to raise_error
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end
end
