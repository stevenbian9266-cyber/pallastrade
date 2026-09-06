# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-1 AC-4P1-03/04/05/06/07/10 (+ AC-4P5-08 capability)
require 'rails_helper'

# FIN-P4-5：无 fetch_financial_details 实现的 PaymentMethod 子类（模拟 legacy PSP：base 契约 default raise）。
module PallasTrade
  class PaymentMethod::NoFinancialDetailsProbe < PaymentMethod
    def source_required?
      false
    end
  end
end

RSpec.describe PallasTrade::FinancialFacts::CaptureEvidencePolicy, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def verdict!(payment)
    described_class.call(payment: payment).value
  end

  it 'AC-4P1-03/04 PSP auto-captured payment (completed + capture event) → :captured with captured amount' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'completed')
    create(:payment_capture_event, payment: payment, amount: 100.0)

    v = verdict!(payment)
    expect(v[:verdict]).to eq(:captured)
    expect(v[:captured_amount]).to eq(100.0)
    expect(v[:evidence]).to include(:capture_event_present)
  end

  it 'AC-4P1-03 partial capture uses accumulated capture events' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'completed')
    create(:payment_capture_event, payment: payment, amount: 40.0)

    v = verdict!(payment)
    expect(v[:verdict]).to eq(:captured)
    expect(v[:captured_amount]).to eq(40.0)
  end

  it 'AC-4P1-10 completed PSP payment without capture evidence → :ambiguous (evidence conflict)' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'completed')

    v = verdict!(payment)
    expect(v[:verdict]).to eq(:ambiguous)
    expect(v[:evidence]).to include(:completed_without_capture_evidence)
  end

  it 'AC-4P1-07 combination payment (completed + combination succeeded) → :captured' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    payment = create(:payment, payment_method: payment_method, amount: 100, state: 'completed',
                               order: nil, payment_combination: combo, source: nil,
                               skip_source_requirement: true)

    v = verdict!(payment)
    expect(v[:verdict]).to eq(:captured)
    expect(v[:evidence]).to include(:combination_succeeded)
    expect(v[:captured_amount]).to eq(100.0)
  end

  it 'AC-4P1-10 combination payment completed but combination not succeeded → :ambiguous' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'pending')
    payment = create(:payment, payment_method: payment_method, amount: 100, state: 'completed',
                               order: nil, payment_combination: combo, source: nil,
                               skip_source_requirement: true)

    v = verdict!(payment)
    expect(v[:verdict]).to eq(:ambiguous)
    expect(v[:evidence]).to include(:combination_not_succeeded)
  end

  it 'AC-4P1-05 manual authorization (pending) → :authorized_only, never captured' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'pending')

    v = verdict!(payment)
    expect(v[:verdict]).to eq(:authorized_only)
  end

  it 'AC-4P1-06 processing (in-flight) → :ambiguous' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'processing')

    v = verdict!(payment)
    expect(v[:verdict]).to eq(:ambiguous)
    expect(v[:evidence]).to include(:payment_processing_inflight)
  end

  it 'AC-4P1-03 failed/void → :unpaid' do
    %w[failed void invalid].each do |state|
      payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: state)
      expect(verdict!(payment)[:verdict]).to eq(:unpaid), "expected #{state} → unpaid"
    end
  end

  it 'AC-4P1-03 checkout (not started) → :unpaid' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'checkout')
    expect(verdict!(payment)[:verdict]).to eq(:unpaid)
  end

  describe 'provider capability (FR-4P1-32~35)' do
    it 'AC-4P1-21 Stripe local capture resolution = supported; Adyen/PayPal unsupported' do
      expect(described_class.local_capture_resolution_supported?(double(type: 'PallasTradeStripe::Gateway'))).to be(true)
      expect(described_class.local_capture_resolution_supported?(double(type: 'PallasTradeAdyen::Gateway'))).to be(false)
      expect(described_class.local_capture_resolution_supported?(double(type: 'PallasTradePaypalCheckout::Gateway'))).to be(false)
    end

    it 'AC-4P1-21/AC-4P5-08 StoreCredit/Offline = NOT_APPLICABLE; Bogus(已实现) = SUPPORTED; legacy PSP = UNSUPPORTED' do
      sc = create(:store_credit_payment_method, store: store)
      check = create(:check_payment_method, store: store)
      bogus = create(:bogus_payment_method, store: store)
      # 无 fetch_financial_details 实现的 PaymentMethod 子类 → UNSUPPORTED（P4 §41 不误报）
      legacy = PallasTrade::PaymentMethod::NoFinancialDetailsProbe.new(
        store: store, name: 'Legacy PSP', type: 'PallasTrade::PaymentMethod::NoFinancialDetailsProbe'
      )
      expect(described_class.provider_reconciliation_capability(sc)).to eq('NOT_APPLICABLE')
      expect(described_class.provider_reconciliation_capability(check)).to eq('NOT_APPLICABLE')
      expect(described_class.provider_reconciliation_capability(bogus)).to eq('PROVIDER_RECONCILIATION_SUPPORTED')
      expect(described_class.provider_reconciliation_capability(legacy)).to eq('PROVIDER_RECONCILIATION_UNSUPPORTED')
    end
  end
end
