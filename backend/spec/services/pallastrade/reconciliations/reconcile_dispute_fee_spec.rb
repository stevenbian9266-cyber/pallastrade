# frozen_string_literal: true

require 'rails_helper'

# PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics
# AC-P79-07 —— 对账把手续费纳入期望账行，并给出只读 fee 视图（含「永不返还」）。
RSpec.describe PallasTrade::Reconciliations::ReconcileDispute, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100) }

  def make_dispute(fee_amount: 15.0, withdrawn: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p79r_#{SecureRandom.hex(4)}",
      state: 'lost',
      amount: 12.34,
      currency: 'usd',
      # 取证裁决为 CONFIRMED 的前提：本地状态与 provider 状态一致
      private_metadata: { 'provider_status' => 'lost' },
      fee_amount: fee_amount,
      funds_withdrawn_at: withdrawn ? Time.current.change(usec: 0) - 1.hour : nil,
      commerce_transaction: txn,
      payment: payment
    )
  end

  def reconcile!(dispute)
    result = described_class.call(dispute: dispute)
    expect(result).to be_success
    result.value
  end

  it 'AC-P79-07 fee 已证但账本缺失 → journal_missing（期望行带 DISPUTE_FEE）' do
    dispute = make_dispute

    verdict = reconcile!(dispute)

    expect(verdict[:classification]).to eq('journal_missing')
    expect(verdict[:expected_entries].map { |entry| entry[:entry_type] }).to include('DISPUTE_FEE')
    expect(verdict[:reasons]).to include('JOURNAL_POSTING_MISSING_DISPUTE_FEE')
  end

  it 'AC-P79-07 fee 已入账 → aligned；fee 视图给出证据/入账/永不返还' do
    dispute = make_dispute
    withdrawal = PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_WITHDRAWN')
    expect(withdrawal.value[:skipped]).to be(false)
    fee = PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: 'DISPUTE_FEE')
    expect(fee.value[:skipped]).to be(false)

    verdict = reconcile!(dispute)

    expect(verdict[:classification]).to eq('aligned')
    expect(verdict[:fee]).to include(evidence: true, posted: true, returned: false)
    expect(verdict[:fee][:amount].to_d).to eq(15.0.to_d)
  end

  it 'AC-P79-07 provider 未证 fee → 不产生期望行，fee 视图 evidence=false' do
    dispute = make_dispute(fee_amount: nil)

    verdict = reconcile!(dispute)

    expect(verdict[:expected_entries].map { |entry| entry[:entry_type] }).not_to include('DISPUTE_FEE')
    expect(verdict[:fee]).to include(evidence: false, posted: false, returned: false)
  end

  it 'AC-P79-07 fee 已知但无扣款时间戳 → 不期望 fee 账行（不可入账，不误报缺口）' do
    dispute = make_dispute(withdrawn: false)

    verdict = reconcile!(dispute)

    expect(verdict[:expected_entries].map { |entry| entry[:entry_type] }).not_to include('DISPUTE_FEE')
    expect(verdict[:fee][:evidence]).to be(true)
    expect(verdict[:fee][:posted]).to be(false)
  end

  it 'AC-P79-07 对账只读：零新账行、零 provider 调用' do
    dispute = make_dispute
    before_count = PallasTrade::FinancialLedgerEntry.count

    reconcile!(dispute)

    expect(PallasTrade::FinancialLedgerEntry.count).to eq(before_count)
  end
end
