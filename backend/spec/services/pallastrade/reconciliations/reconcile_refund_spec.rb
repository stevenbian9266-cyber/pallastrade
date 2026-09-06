# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-6 AC-4P6-06/07/08/09
require 'rails_helper'

module PallasTrade
  class PaymentMethod::ReconcileRefundProbe < PaymentMethod
    def source_required?
      false
    end
  end
end

RSpec.describe PallasTrade::Reconciliations::ReconcileRefund, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def completed_payment(pm:)
    create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed',
                     source: nil, skip_source_requirement: true)
  end

  def reconcile!(refund)
    described_class.call(refund: refund)
  end

  it 'AC-4P6-06 local refund == provider refund (reference-linked) → MATCHED' do
    pm = create(:bogus_payment_method, store: store, active: true)
    refund = create(:refund, payment: completed_payment(pm: pm), amount: 20, transaction_id: 're_ok_1')

    result = reconcile!(refund)
    expect(result).to be_success
    expect(result.value).to be_matched
    expect(result.value.local_amount).to eq(20.0)
    expect(result.value.provider_gross_amount).to eq(20.0)
    expect(result.value.provider_payment_reference).to eq('re_ok_1')
  end

  it 'AC-4P6-07 refund amount mismatch → MISMATCH + REFUND_MISMATCH (no auto-refund)' do
    pm = create(:bogus_payment_method, store: store, active: true)
    refund = create(:refund, payment: completed_payment(pm: pm), amount: 20, transaction_id: 're_mis_1')
    allow(pm).to receive(:fetch_refund_details).and_return(
      provider_refund_reference: 're_mis_1', amount: 10.0, currency: 'USD', status: 'succeeded'
    )
    refunds_before = PallasTrade::Refund.count

    result = reconcile!(refund)
    expect(result.value).to be_mismatch
    expect(result.value.reasons).to eq(['REFUND_MISMATCH'])
    expect(PallasTrade::Refund.count).to eq(refunds_before)
  end

  it 'AC-4P6-07 currency mismatch → MISMATCH + CURRENCY_MISMATCH' do
    pm = create(:bogus_payment_method, store: store, active: true)
    refund = create(:refund, payment: completed_payment(pm: pm), amount: 20, transaction_id: 're_cur_1')
    allow(pm).to receive(:fetch_refund_details).and_return(
      provider_refund_reference: 're_cur_1', amount: 20.0, currency: 'EUR', status: 'succeeded'
    )

    result = reconcile!(refund)
    expect(result.value).to be_mismatch
    expect(result.value.reasons).to eq(['CURRENCY_MISMATCH'])
  end

  it 'AC-4P6-08 refund on Check/StoreCredit → NOT_APPLICABLE' do
    pm = create(:check_payment_method, store: store)
    refund = create(:refund, payment: completed_payment(pm: pm), amount: 20, transaction_id: 're_na_1')

    result = reconcile!(refund)
    expect(result.value).to be_not_applicable
  end

  it 'AC-4P6-08 legacy provider without refund contract → UNSUPPORTED (not MISMATCH)' do
    pm = PallasTrade::PaymentMethod::ReconcileRefundProbe.new(
      store: store, name: 'Legacy', type: 'PallasTrade::PaymentMethod::ReconcileRefundProbe'
    )
    refund = create(:refund, payment: completed_payment(pm: pm), amount: 20, transaction_id: 're_uns_1')

    result = reconcile!(refund)
    expect(result.value).to be_unsupported
    expect(result.value.reasons).to eq(['PROVIDER_CONTRACT_UNSUPPORTED'])
  end

  it 'local refund without provider reference → NEEDS_ATTENTION + UNLINKED_LEGACY_PAYMENT' do
    pm = create(:bogus_payment_method, store: store, active: true)
    refund = create(:refund, payment: completed_payment(pm: pm), amount: 20, transaction_id: 're_tmp_1')
    refund.update_column(:transaction_id, nil)

    result = reconcile!(refund)
    expect(result.value).to be_needs_attention
    expect(result.value.reasons).to eq(['UNLINKED_LEGACY_PAYMENT'])
  end

  it 'provider error → NEEDS_ATTENTION + PROVIDER_UNAVAILABLE (idempotent, read-only)' do
    pm = create(:bogus_payment_method, store: store, active: true)
    refund = create(:refund, payment: completed_payment(pm: pm), amount: 20, transaction_id: 're_err_1')
    allow(pm).to receive(:fetch_refund_details).and_raise(PallasTrade::Core::GatewayError, 'boom')

    first = reconcile!(refund).value
    expect(first).to be_needs_attention
    expect(first.reasons).to eq(['PROVIDER_UNAVAILABLE'])
    expect(first.provider_error).to be_present
    expect(reconcile!(refund).value.status).to eq(first.status)
    expect(refund.reload.transaction_id).to eq('re_err_1')
  end

  it 'nil refund → failure' do
    expect(described_class.call(refund: nil)).to be_failure
  end
end
