# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-3 AC-4P3-01/02/03/04/05/08/09
require 'rails_helper'

# UNKNOWN-instrument 测试用 PaymentMethod（同 resolve_payment_spec 模式：source_required?=false
# 使 Payment 可创建，provider_class 保持基类 raise → InstrumentClassifier → UNKNOWN）。
module PallasTrade
  class PaymentMethod::FinancialLedgerPostingProbe < PaymentMethod
    def source_required?
      false
    end
  end
end

RSpec.describe PallasTrade::FinancialLedger::PostPayment, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def make_transaction(amount: 100, combo: nil)
    PallasTrade::CommerceTransaction.create!(
      { store: store, purpose: 'purchase', currency: 'USD', amount: amount }.merge(
        combo ? { payment_combination: combo } : {}
      )
    )
  end

  def make_session(txn:, pm: payment_method, status: 'pending', amount: 100)
    create(:bogus_payment_session, order: order, payment_method: pm, status: status, amount: amount,
                                   currency: 'USD', commerce_transaction: txn)
  end

  def post!(payment)
    described_class.call(payment: payment)
  end

  describe 'PSP cash posting (AC-4P3-01/02/04/05)' do
    it 'AC-4P3-01 reliable auto-capture (real confirm! path) → exactly one CASH_CAPTURED entry on the txn' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: true)
      txn = make_transaction
      session = make_session(txn: txn, pm: pm)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'checkout',
                                 payment_session: session)
      payment.confirm! # real path → completed + PaymentCaptureEvent
      expect(payment).to be_completed
      expect(payment.capture_events).not_to be_empty

      result = post!(payment)
      expect(result).to be_success
      payload = result.value
      expect(payload[:skipped]).to be(false)
      entry = payload[:entry]
      expect(entry).to be_a(PallasTrade::FinancialLedgerEntry)
      expect(entry.entry_type).to eq('CASH_CAPTURED')
      expect(entry.amount).to eq(100.0)
      expect(entry.currency).to eq('USD')
      expect(entry.commerce_transaction).to eq(txn)
      expect(entry.payment).to eq(payment)
      expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'CASH_CAPTURED').count).to eq(1)
    end

    it 'AC-4P3-01 manual capture (real capture! model path) → one CASH_CAPTURED entry' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: false)
      txn = make_transaction
      session = make_session(txn: txn, pm: pm)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'checkout',
                                 payment_session: session)
      payment.confirm!
      expect(payment.state).to eq('pending')

      allow(pm).to receive(:capture).and_return(
        PallasTrade::PaymentResponse.new(true, 'ok', {}, authorization: 'BGS-captured-1',
                                          avs_result: { code: 'Y' }, cvv_result: { code: 'M', message: 'Match' })
      )
      payment.capture!(100_00)
      expect(payment).to be_completed

      result = post!(payment)
      expect(result).to be_success
      expect(result.value[:entry].entry_type).to eq('CASH_CAPTURED')
      expect(result.value[:entry].commerce_transaction).to eq(txn)
    end

    it 'AC-4P3-02 idempotent: repeated PostPayment for the same payment → same single entry' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: true)
      txn = make_transaction
      session = make_session(txn: txn, pm: pm)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'checkout',
                                 payment_session: session)
      payment.confirm!

      first = post!(payment).value[:entry]
      second = post!(payment).value[:entry]
      expect(second.id).to eq(first.id)
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(1)
    end

    it 'AC-4P3-04 balance collection (independent txn) → its own entry on that txn' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: true)
      # 主订单先经 txn1 支付 60
      txn1 = make_transaction(amount: 100)
      s1 = make_session(txn: txn1, pm: pm, amount: 60)
      p1 = create(:payment, order: order, payment_method: pm, amount: 60, state: 'checkout', payment_session: s1)
      p1.confirm!
      post!(p1)

      # balance collection：独立补付 session → 独立 txn2 → 独立 entry
      txn2 = make_transaction(amount: 40)
      s2 = make_session(txn: txn2, pm: pm, amount: 40)
      p2 = create(:payment, order: order, payment_method: pm, amount: 40, state: 'checkout', payment_session: s2)
      p2.confirm!

      result = post!(p2)
      expect(result).to be_success
      entry = result.value[:entry]
      expect(entry.commerce_transaction).to eq(txn2)
      expect(entry.amount).to eq(40.0)
      expect(PallasTrade::FinancialLedgerEntry.where(commerce_transaction_id: txn2.id).count).to eq(1)
      expect(PallasTrade::FinancialLedgerEntry.where(commerce_transaction_id: txn1.id).count).to eq(1)
    end

    it 'AC-4P3-05 combination payment → one cash entry on the combination txn (splits add no entries)' do
      combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
      txn = make_transaction(amount: 100, combo: combo)
      payment = create(:payment, payment_method: payment_method, amount: 100, state: 'completed',
                                 order: nil, payment_combination: combo, source: nil,
                                 skip_source_requirement: true)
      create(:payment_capture_event, payment: payment, amount: 100.0)
      # 两个成员订单 splits（P4-4 才产生 ORDER_ALLOCATION——本期不产生任何额外 entry）
      o1 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 60, total: 60)
      o2 = create(:order, store: store, state: 'pending', status: 'placed', item_total: 40, total: 40)
      create(:payment_split, payment_combination: combo, order: o1, payment: payment, currency: 'USD', captured_amount: 60)
      create(:payment_split, payment_combination: combo, order: o2, payment: payment, currency: 'USD', captured_amount: 40)

      result = post!(payment)
      expect(result).to be_success
      expect(result.value[:skipped]).to be(false)
      entry = result.value[:entry]
      expect(entry.entry_type).to eq('CASH_CAPTURED')
      expect(entry.commerce_transaction).to eq(txn)
      expect(entry.payment_combination).to eq(combo)
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(1)
    end
  end

  describe 'StoreCredit / Offline posting (AC-4P3-03)' do
    it 'AC-4P3-03 store credit completed → STORE_CREDIT_APPLIED entry (never CASH_CAPTURED)' do
      user = create(:user)
      credit = create(:store_credit, store: store, user: user, amount: 200.0, currency: 'USD')
      order_sc = create(:order, store: store, user: user, state: 'pending', status: 'placed',
                                item_total: 100, total: 100, payment_state: 'balance_due')
      pm = create(:store_credit_payment_method, store: store, active: true)
      txn = make_transaction
      session = create(:bogus_payment_session, order: order_sc, payment_method: pm, status: 'completed',
                                               amount: 100, currency: 'USD', commerce_transaction: txn)
      payment = create(:payment, order: order_sc, payment_method: pm, amount: 100,
                                 state: 'completed', source: credit, payment_session: session)

      result = post!(payment)
      expect(result).to be_success
      expect(result.value[:skipped]).to be(false)
      entry = result.value[:entry]
      expect(entry.entry_type).to eq('STORE_CREDIT_APPLIED')
      expect(entry.commerce_transaction).to eq(txn)
      expect(entry.amount).to eq(100.0)
    end

    it 'AC-4P3-03 offline/check completed → OFFLINE_PAYMENT_RECORDED entry' do
      pm = create(:check_payment_method, store: store)
      txn = make_transaction
      session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'completed',
                                               amount: 100, currency: 'USD', commerce_transaction: txn)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed',
                                 payment_session: session, source: nil, skip_source_requirement: true)

      result = post!(payment)
      expect(result).to be_success
      expect(result.value[:skipped]).to be(false)
      entry = result.value[:entry]
      expect(entry.entry_type).to eq('OFFLINE_PAYMENT_RECORDED')
      expect(entry.commerce_transaction).to eq(txn)
    end
  end

  describe 'skip semantics (AC-4P3-09) + read-only (AC-4P3-08)' do
    it 'AC-4P3-09 AMBIGUOUS (completed without capture evidence) → skipped, no entry, no guess' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: true)
      txn = make_transaction
      session = make_session(txn: txn, pm: pm)
      payment = create(:payment, order: order, payment_method: pm, amount: 100,
                                 state: 'completed', payment_session: session) # no capture event

      result = post!(payment)
      expect(result).to be_success
      expect(result.value[:skipped]).to be(true)
      expect(result.value[:entry]).to be_nil
      expect(result.value[:reason]).to eq('fact_status_not_confirmed')
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
    end

    it 'AC-4P3-09 UNSUPPORTED instrument → skipped (never posted as cash)' do
      pm = PallasTrade::PaymentMethod::FinancialLedgerPostingProbe.create!(store: store, name: 'Unknown probe')
      payment = create(:payment, order: order, payment_method: pm, amount: 100,
                                 state: 'completed', source: nil)

      result = post!(payment)
      expect(result).to be_success
      expect(result.value[:skipped]).to be(true)
      expect(result.value[:reason]).to eq('fact_status_not_confirmed')
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
    end

    it 'AC-4P3-09 CONFIRMED but no resolvable commerce transaction → skipped' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: true)
      payment = create(:payment, order: order, payment_method: pm, amount: 100,
                                 state: 'completed') # no session / combination
      create(:payment_capture_event, payment: payment, amount: 100.0)

      result = post!(payment)
      expect(result).to be_success
      expect(result.value[:skipped]).to be(true)
      expect(result.value[:reason]).to eq('commerce_transaction_missing')
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
    end

    it 'AC-4P3-08 posting is read-only for payment/order/txn (no new payment, no state change)' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: true)
      txn = make_transaction
      session = make_session(txn: txn, pm: pm)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'checkout',
                                 payment_session: session)
      payment.confirm!
      before_state = payment.state
      payments_before = PallasTrade::Payment.count
      txns_before = PallasTrade::CommerceTransaction.count

      expect(payment).not_to receive(:save)
      expect(payment).not_to receive(:update)

      result = post!(payment)
      expect(result).to be_success
      expect(result.value[:skipped]).to be(false)
      expect(payment.reload.state).to eq(before_state)
      expect(PallasTrade::Payment.count).to eq(payments_before)
      expect(PallasTrade::CommerceTransaction.count).to eq(txns_before)
    end

    it 'AC-4P3-08 posting failure does not affect payment (nil payment → failure)' do
      result = described_class.call(payment: nil)
      expect(result).to be_failure
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
    end
  end
end
