# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-6 AC-4P6-01/02/03/04/05/08/09
require 'rails_helper'

module PallasTrade
  class PaymentMethod::ReconcileProbe < PaymentMethod
    def source_required?
      false
    end
  end
end

RSpec.describe PallasTrade::Reconciliations::ReconcilePayment, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def bogus_pm
    create(:bogus_payment_method, store: store, active: true)
  end

  def reconcile!(payment)
    described_class.call(payment: payment)
  end

  # payment + 真实 capture 证据 + session（provider 锚点）
  def captured_payment(pm:, session_status: 'completed', amount: 100, session_amount: nil, capture_event: true)
    session = create(:bogus_payment_session, order: order, payment_method: pm,
                                             status: session_status, amount: session_amount || amount,
                                             currency: 'USD')
    payment = create(:payment, order: order, payment_method: pm, amount: amount,
                               state: 'completed', payment_session: session,
                               source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: amount.to_f) if capture_event
    payment
  end

  it 'AC-4P6-01 local captured == provider gross (settled) → MATCHED' do
    pm = bogus_pm
    payment = captured_payment(pm: pm)

    result = reconcile!(payment)
    expect(result).to be_success
    expect(result.value).to be_matched
    expect(result.value.local_amount).to eq(100.0)
    expect(result.value.provider_gross_amount).to eq(100.0)
    expect(result.value.provider_settlement_status).to eq('settled')
    expect(result.value.reasons).to eq([])
  end

  it 'AC-4P6-02 amount mismatch → MISMATCH + AMOUNT_MISMATCH (no payment change)' do
    pm = bogus_pm
    payment = captured_payment(pm: pm, amount: 90, session_amount: 100) # local 90 vs provider 100
    amount_before = payment.reload.amount

    result = reconcile!(payment)
    expect(result.value).to be_mismatch
    expect(result.value.reasons).to include('AMOUNT_MISMATCH')
    expect(payment.reload.amount).to eq(amount_before)
    expect(payment.state).to eq('completed')
  end

  it 'AC-4P6-03 settlement pending → PENDING + SETTLEMENT_PENDING (no mismatch alarm)' do
    pm = bogus_pm
    payment = captured_payment(pm: pm, session_status: 'pending')

    result = reconcile!(payment)
    expect(result.value).to be_pending
    expect(result.value.reasons).to eq(['SETTLEMENT_PENDING'])
  end

  it 'AC-4P6-04 provider error → NEEDS_ATTENTION + PROVIDER_UNAVAILABLE; re-run is idempotent' do
    pm = bogus_pm
    payment = captured_payment(pm: pm)
    allow(pm).to receive(:fetch_financial_details).and_raise(PallasTrade::Core::GatewayError, 'boom')

    first = reconcile!(payment).value
    second = reconcile!(payment).value
    expect(first).to be_needs_attention
    expect(first.reasons).to eq(['PROVIDER_UNAVAILABLE'])
    expect(first.provider_error).to be_present
    expect(second.status).to eq(first.status)
  end

  it 'AC-4P6-05 local not captured but provider settled → NEEDS_ATTENTION + LOCAL_PAYMENT_MISSING' do
    pm = bogus_pm
    session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'completed',
                                             amount: 100, currency: 'USD')
    payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'checkout',
                               payment_session: session, source: nil, skip_source_requirement: true)

    result = reconcile!(payment)
    expect(result.value).to be_needs_attention
    expect(result.value.reasons).to eq(['LOCAL_PAYMENT_MISSING'])
  end

  it 'AC-4P6-08 StoreCredit/Check → NOT_APPLICABLE' do
    check_pm = create(:check_payment_method, store: store)
    payment = create(:payment, order: order, payment_method: check_pm, amount: 100, state: 'completed',
                               source: nil, skip_source_requirement: true)
    result = reconcile!(payment)
    expect(result.value).to be_not_applicable
  end

  it 'AC-4P6-08 legacy provider without financial-details contract → UNSUPPORTED (not MISMATCH)' do
    pm = PallasTrade::PaymentMethod::ReconcileProbe.new(
      store: store, name: 'Legacy', type: 'PallasTrade::PaymentMethod::ReconcileProbe'
    )
    payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed',
                               source: nil, skip_source_requirement: true)

    result = reconcile!(payment)
    expect(result.value).to be_unsupported
    expect(result.value.reasons).to eq(['PROVIDER_CONTRACT_UNSUPPORTED'])
  end

  it 'AC-4P6-09 read-only: zero writes, zero state change, repeatable' do
    pm = bogus_pm
    payment = captured_payment(pm: pm)
    payments_before = PallasTrade::Payment.count
    entries_before = PallasTrade::FinancialLedgerEntry.count

    first = reconcile!(payment)
    expect(first.value).to be_matched
    expect(payment.reload.state).to eq('completed')
    expect(PallasTrade::Payment.count).to eq(payments_before)
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(entries_before)
    expect(reconcile!(payment).value.status).to eq(first.value.status)
  end

  it 'payment without a provider session anchor → NEEDS_ATTENTION + UNLINKED_LEGACY_PAYMENT' do
    pm = bogus_pm
    payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed',
                               source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)

    result = reconcile!(payment)
    expect(result.value).to be_needs_attention
    expect(result.value.reasons).to eq(['UNLINKED_LEGACY_PAYMENT'])
  end

  it 'nil payment → failure' do
    expect(described_class.call(payment: nil)).to be_failure
  end
end
