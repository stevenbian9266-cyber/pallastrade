# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-3 AC-4P3-06/07/08/09
require 'rails_helper'

RSpec.describe PallasTrade::FinancialLedger::PostRefund, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def make_transaction(amount: 100)
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: amount)
  end

  # captured payment（真实 capture 证据）绑到 session→txn（ownership 可靠路径）
  def captured_payment(txn: nil, amount: 100)
    payment = create(:payment, order: order, payment_method: payment_method, amount: amount,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: amount.to_f)
    if txn
      session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                               amount: amount, currency: 'USD', commerce_transaction: txn)
      payment.update_column(:payment_session_id, session.id)
    end
    payment
  end

  def post!(refund)
    described_class.call(refund: refund)
  end

  it 'AC-4P3-06 successful refund → exactly one REFUND_SUCCEEDED entry on the txn' do
    txn = make_transaction
    payment = captured_payment(txn: txn)
    refund = create(:refund, payment: payment, amount: 20, transaction_id: 're_stripe_1')

    result = post!(refund)
    expect(result).to be_success
    payload = result.value
    expect(payload[:skipped]).to be(false)
    entry = payload[:entry]
    expect(entry).to be_a(PallasTrade::FinancialLedgerEntry)
    expect(entry.entry_type).to eq('REFUND_SUCCEEDED')
    expect(entry.amount).to eq(20.0)
    expect(entry.currency).to eq('USD')
    expect(entry.commerce_transaction).to eq(txn)
    expect(entry.payment).to eq(payment)
    expect(entry.refund).to eq(refund)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'REFUND_SUCCEEDED').count).to eq(1)
  end

  it 'AC-4P3-07 multiple partial refunds → independent entries (never aggregated)' do
    txn = make_transaction
    payment = captured_payment(txn: txn)
    r1 = create(:refund, payment: payment, amount: 20, transaction_id: 're_a')
    r2 = create(:refund, payment: payment, amount: 10, transaction_id: 're_b')

    e1 = post!(r1).value[:entry]
    e2 = post!(r2).value[:entry]
    expect(e1.amount).to eq(20.0)
    expect(e2.amount).to eq(10.0)
    expect(e1.refund_id).not_to eq(e2.refund_id)
    expect(e1.refund).to eq(r1)
    expect(e2.refund).to eq(r2)
    expect(e1.commerce_transaction).to eq(txn)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'REFUND_SUCCEEDED').count).to eq(2)
  end

  it 'AC-4P3-02 idempotent: repeated PostRefund → same single entry' do
    txn = make_transaction
    payment = captured_payment(txn: txn)
    refund = create(:refund, payment: payment, amount: 20, transaction_id: 're_idem')

    first = post!(refund).value[:entry]
    second = post!(refund).value[:entry]
    expect(second.id).to eq(first.id)
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(1)
  end

  it 'AC-4P3-09 refund without provable provider reference → skipped (no guess), no entry' do
    txn = make_transaction
    payment = captured_payment(txn: txn)
    refund = create(:refund, payment: payment, amount: 10, transaction_id: 're_tmp')
    refund.update_column(:transaction_id, nil) # 历史/手工记录缺 provider ref

    result = post!(refund)
    expect(result).to be_success
    expect(result.value[:skipped]).to be(true)
    expect(result.value[:reason]).to eq('fact_status_not_confirmed')
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-4P3-09 CONFIRMED refund without resolvable transaction → skipped' do
    payment = captured_payment # no session → ownership :none
    refund = create(:refund, payment: payment, amount: 10, transaction_id: 're_no_txn')

    result = post!(refund)
    expect(result).to be_success
    expect(result.value[:skipped]).to be(true)
    expect(result.value[:reason]).to eq('commerce_transaction_missing')
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end

  it 'AC-4P3-08 posting is read-only for refund/payment/txn' do
    txn = make_transaction
    payment = captured_payment(txn: txn)
    refund = create(:refund, payment: payment, amount: 20, transaction_id: 're_ro')
    refunds_before = PallasTrade::Refund.count
    payments_before = PallasTrade::Payment.count
    txn_id_before = refund.reload.transaction_id

    expect(refund).not_to receive(:save)
    expect(refund).not_to receive(:update)

    result = post!(refund)
    expect(result).to be_success
    expect(result.value[:skipped]).to be(false)
    expect(refund.reload.transaction_id).to eq(txn_id_before)
    expect(PallasTrade::Refund.count).to eq(refunds_before)
    expect(PallasTrade::Payment.count).to eq(payments_before)
  end

  it 'AC-4P3-08 nil refund → failure, no entry' do
    result = described_class.call(refund: nil)
    expect(result).to be_failure
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
  end
end
