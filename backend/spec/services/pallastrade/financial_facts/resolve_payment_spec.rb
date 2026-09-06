# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-1 AC-4P1-04/05/06/07/08/09/10/11/12/13/16/23
require 'rails_helper'

# UNKNOWN-instrument 测试用 PaymentMethod：source_required?=false 使 Payment 可创建，
# provider_class 保持基类 raise → InstrumentClassifier 返回 UNKNOWN（真实 base PaymentMethod
# 因无 payment_source_class 无法创建 Payment，见 Payment#source）。
module PallasTrade
  class PaymentMethod::FinancialFactUnknownProbe < PaymentMethod
    def source_required?
      false
    end
  end
end

RSpec.describe PallasTrade::FinancialFacts::ResolvePayment, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def make_transaction(purpose: 'purchase', amount: 100, **opts)
    PallasTrade::CommerceTransaction.create!(
      { store: store, purpose: purpose, currency: 'USD', amount: amount }.merge(opts)
    )
  end

  def resolve!(payment, transaction: nil)
    described_class.call(payment: payment, transaction: transaction)
  end

  def psp_captured_payment(amount: 100, session: nil, state: 'completed')
    create(:payment, order: order, payment_method: payment_method, amount: amount, state: state,
                     payment_session: session)
  end

  describe 'PSP_CASH' do
    it 'AC-4P1-04 Stripe/Bogus auto capture (real confirm! path) → CONFIRMED CASH_CAPTURED' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: true)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'checkout')
      payment.confirm! # started_processing → complete! + PaymentCaptureEvent（真实路径）
      expect(payment).to be_completed
      expect(payment.capture_events).not_to be_empty

      fact = resolve!(payment).value
      expect(fact.fact_type).to eq(PallasTrade::FinancialFact::CASH_CAPTURED)
      expect(fact.status).to eq(PallasTrade::FinancialFact::CONFIRMED)
      expect(fact.amount).to eq(100.0)
      expect(fact.provider_payment_reference).to eq(payment.response_code)
      expect(fact.commerce_transaction_id).to be_nil
    end

    it 'AC-4P1-05 manual authorization (real confirm! → pending) → AUTHORIZED_ONLY, not CASH_CAPTURED' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: false)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'checkout')
      payment.confirm! # auto_capture=false → pend!（authorization only）
      expect(payment.state).to eq('pending')

      fact = resolve!(payment).value
      expect(fact.status).to eq(PallasTrade::FinancialFact::AUTHORIZED_ONLY)
      expect(fact.fact_type).to eq(PallasTrade::FinancialFact::NONE)
      expect(fact.reason_code).to eq('authorized_only')
    end

    it 'AC-4P1-06 manual capture (real capture! model method) → CONFIRMED CASH_CAPTURED' do
      pm = create(:bogus_payment_method, store: store, active: true, auto_capture: false)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'checkout')
      payment.confirm!
      expect(payment.state).to eq('pending')

      allow(pm).to receive(:capture).and_return(
        PallasTrade::PaymentResponse.new(true, 'ok', {}, authorization: 'BGS-captured-1',
                                          avs_result: { code: 'Y' }, cvv_result: { code: 'M', message: 'Match' })
      )
      payment.capture!(100_00) # 真实 Payment#capture! → complete! + PaymentCaptureEvent
      expect(payment).to be_completed
      expect(payment.capture_events).not_to be_empty

      fact = resolve!(payment).value
      expect(fact.status).to eq(PallasTrade::FinancialFact::CONFIRMED)
      expect(fact.fact_type).to eq(PallasTrade::FinancialFact::CASH_CAPTURED)
      expect(fact.amount).to eq(100.0)
    end

    it 'AC-4P1-10 completed without capture evidence → AMBIGUOUS (evidence conflict, no guess)' do
      payment = psp_captured_payment # state completed, no PaymentCaptureEvent
      fact = resolve!(payment).value
      expect(fact.status).to eq(PallasTrade::FinancialFact::AMBIGUOUS)
      expect(fact.fact_type).to eq(PallasTrade::FinancialFact::CASH_CAPTURED)
      expect(fact.reason_code).to eq('capture_evidence_ambiguous')
    end

    it 'AC-4P1-16 PSP reference never fabricates commerce_transaction ownership' do
      payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                                 state: 'completed', response_code: 'pi_some_ref')
      create(:payment_capture_event, payment: payment, amount: 100.0)

      fact = resolve!(payment).value
      expect(fact.commerce_transaction_id).to be_nil
    end

    it 'AC-4P1-14 ownership via PaymentSession is surfaced on the fact' do
      txn = make_transaction
      session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                               amount: 100, currency: 'USD', commerce_transaction: txn)
      payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                                 state: 'completed', payment_session: session)
      create(:payment_capture_event, payment: payment, amount: 100.0)

      fact = resolve!(payment).value
      expect(fact.commerce_transaction_id).to eq(txn.prefixed_id)
      expect(fact.payment_session_id).to eq(session.prefixed_id)
    end

    it 'AC-4P1-07 combination payment produces exactly ONE cash fact' do
      combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
      payment = create(:payment, payment_method: payment_method, amount: 100, state: 'completed',
                                 order: nil, payment_combination: combo, source: nil,
                                 skip_source_requirement: true)

      fact = resolve!(payment).value
      expect(fact.fact_type).to eq(PallasTrade::FinancialFact::CASH_CAPTURED)
      expect(fact.status).to eq(PallasTrade::FinancialFact::CONFIRMED)
      expect(fact.amount).to eq(100.0)
      expect(fact.payment_combination_id).to eq(combo.prefixed_id)
      expect(fact.order_id).to be_nil
    end

    it 'AC-4P1-11 amount/currency source conflict → AMBIGUOUS (no silent pick)' do
      session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                               amount: 100, currency: 'EUR', commerce_transaction: nil)
      payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                                 state: 'completed', payment_session: session)
      create(:payment_capture_event, payment: payment, amount: 100.0)

      fact = resolve!(payment).value
      expect(fact.status).to eq(PallasTrade::FinancialFact::AMBIGUOUS)
      expect(fact.reason_code).to eq('currency_source_conflict_or_missing')
    end

    it 'AC-4P1-13 short payment (txn 100 / captured 40) → confirmed fact of 40, not an error' do
      make_transaction # txn 100（ResolvePayment 不把 short 当 error；reconciliation 层面处理）
      payment = create(:payment, order: order, payment_method: payment_method, amount: 40, state: 'completed')
      create(:payment_capture_event, payment: payment, amount: 40.0)

      fact = resolve!(payment).value
      expect(fact.status).to eq(PallasTrade::FinancialFact::CONFIRMED)
      expect(fact.fact_type).to eq(PallasTrade::FinancialFact::CASH_CAPTURED)
      expect(fact.amount).to eq(40.0)
    end

    it 'AC-4P1-12 one CommerceTransaction with N successful payments → N independent confirmed facts' do
      txn = make_transaction
      s1 = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                          amount: 40, currency: 'USD', commerce_transaction: txn)
      p1 = create(:payment, order: order, payment_method: payment_method, amount: 40,
                            state: 'completed', payment_session: s1)
      create(:payment_capture_event, payment: p1, amount: 40.0)

      s2 = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                          amount: 60, currency: 'USD', commerce_transaction: txn)
      p2 = create(:payment, order: order, payment_method: payment_method, amount: 60,
                            state: 'completed', payment_session: s2)
      create(:payment_capture_event, payment: p2, amount: 60.0)

      facts = [p1, p2].map { |p| resolve!(p).value }
      expect(facts.map(&:status).uniq).to eq([PallasTrade::FinancialFact::CONFIRMED])
      expect(facts.map(&:amount)).to eq([40.0, 60.0])
      expect(facts.map(&:commerce_transaction_id).uniq).to eq([txn.prefixed_id])
    end
  end

  describe 'StoreCredit / Offline / Unknown' do
    it 'AC-4P1-08 StoreCredit payment → STORE_CREDIT_APPLIED, never CASH_CAPTURED' do
      user = create(:user)
      credit = create(:store_credit, store: store, user: user, amount: 200.0, currency: 'USD')
      order_sc = create(:order, store: store, user: user, state: 'pending', status: 'placed',
                                item_total: 100, total: 100, payment_state: 'balance_due')
      pm = create(:store_credit_payment_method, store: store, active: true)
      payment = create(:payment, order: order_sc, payment_method: pm, amount: 100,
                                 state: 'completed', source: credit)

      fact = resolve!(payment).value
      expect(fact.fact_type).to eq(PallasTrade::FinancialFact::STORE_CREDIT_APPLIED)
      expect(fact.status).to eq(PallasTrade::FinancialFact::CONFIRMED)
      expect(fact.amount).to eq(100.0)
      expect(fact.instrument_class).to eq(PallasTrade::FinancialFact::STORE_CREDIT)
    end

    it 'AC-4P1-09 Check/offline payment → OFFLINE_PAYMENT_RECORDED' do
      pm = create(:check_payment_method, store: store)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed',
                                 source: nil, skip_source_requirement: true)

      fact = resolve!(payment).value
      expect(fact.fact_type).to eq(PallasTrade::FinancialFact::OFFLINE_PAYMENT_RECORDED)
      expect(fact.status).to eq(PallasTrade::FinancialFact::CONFIRMED)
      expect(fact.instrument_class).to eq(PallasTrade::FinancialFact::OFFLINE)
    end

    it 'AC-4P1-10 unknown/legacy instrument → UNSUPPORTED (never guessed as PSP cash)' do
      # 直接用 probe 类构造（STI type 与对象类一致；factory 只设 type 不会切换对象类）
      pm = PallasTrade::PaymentMethod::FinancialFactUnknownProbe.create!(store: store, name: 'Unknown probe')
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed', source: nil)

      fact = resolve!(payment).value
      expect(fact.instrument_class).to eq(PallasTrade::FinancialFact::UNKNOWN)
      expect(fact.status).to eq(PallasTrade::FinancialFact::UNSUPPORTED)
      expect(fact.fact_type).to eq(PallasTrade::FinancialFact::NONE)
    end
  end

  describe 'read-only boundary' do
    it 'AC-4P1-23 resolution performs no DB writes / no side-effect calls' do
      payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'completed')
      create(:payment_capture_event, payment: payment, amount: 100.0)
      before_state = payment.state

      expect(payment).not_to receive(:save)
      expect(payment).not_to receive(:save!)
      expect(payment).not_to receive(:update)
      expect(payment).not_to receive(:confirm!)
      expect(payment).not_to receive(:capture!)

      fact = resolve!(payment).value
      expect(fact).to be_present
      expect(payment.reload.state).to eq(before_state)
    end
  end
end
