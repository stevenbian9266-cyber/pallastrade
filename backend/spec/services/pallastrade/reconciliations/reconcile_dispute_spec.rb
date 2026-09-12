# frozen_string_literal: true

require 'rails_helper'

# PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile AC-P73-10
# `Reconciliations::ReconcileDispute` —— Dispute ↔ 本地 Journal 只读对账：
#   期望账行 = funds 时间戳集合；五类分类 + 零写零触网。
RSpec.describe PallasTrade::Reconciliations::ReconcileDispute, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100) }

  def make_dispute(state: 'needs_response', funds_withdrawn_at: nil, funds_reinstated_at: nil, amount: 12.34)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_#{SecureRandom.hex(4)}",
      state: state, amount: amount, currency: 'usd',
      private_metadata: { 'provider_status' => state },
      funds_withdrawn_at: funds_withdrawn_at,
      funds_reinstated_at: funds_reinstated_at,
      commerce_transaction: txn, payment: payment
    )
  end

  def reconcile(dispute)
    result = described_class.call(dispute: dispute)

    expect(result).to be_success
    result.value
  end

  # 直接落一条账行（绕过 posting：构造 mismatch / orphan 场景）
  def raw_entry(dispute, entry_type:, amount:, currency: 'USD', key: nil)
    PallasTrade::FinancialLedgerEntry.create!(
      commerce_transaction: txn, dispute: dispute, payment: payment,
      entry_type: entry_type, amount: amount, currency: currency,
      effective_at: Time.current, idempotency_key: key || "raw:#{dispute.id}:#{entry_type}:#{SecureRandom.hex(3)}"
    )
  end

  it 'AC-P73-10 aligned：资金事实已入账且金额币种一致' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)
    PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute)

    payload = reconcile(dispute)

    expect(payload[:classification]).to eq('aligned')
    expect(payload[:reasons]).to eq([])
    expect(payload[:expected_entries].map { |e| e[:entry_type] }).to eq(['DISPUTE_FUNDS_WITHDRAWN'])
    expect(payload[:entries].size).to eq(1)
    expect(payload[:capability]).to eq('JOURNAL_LOCAL_ONLY')
  end

  it 'AC-P73-10 won + 扣回/返还各一条 → aligned（终态不吞资金事件）' do
    dispute = make_dispute(state: 'won', funds_withdrawn_at: 3.days.ago, funds_reinstated_at: 1.day.ago)
    PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_WITHDRAWN')
    PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_REINSTATED')

    payload = reconcile(dispute)

    expect(payload[:classification]).to eq('aligned')
    expect(payload[:expected_entries].map { |e| e[:entry_type] }).to contain_exactly(
      'DISPUTE_FUNDS_WITHDRAWN', 'DISPUTE_FUNDS_REINSTATED'
    )
  end

  it 'AC-P73-10 journal_missing：有资金事实但无账行（subscriber 丢失窗口）' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)

    payload = reconcile(dispute)

    expect(payload[:classification]).to eq('journal_missing')
    expect(payload[:reasons]).to eq(['JOURNAL_POSTING_MISSING_DISPUTE_FUNDS_WITHDRAWN'])
  end

  it 'AC-P73-10 amount_mismatch：账行金额与事实不符' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)
    raw_entry(dispute, entry_type: 'DISPUTE_FUNDS_WITHDRAWN', amount: -99.99)

    payload = reconcile(dispute)

    expect(payload[:classification]).to eq('amount_mismatch')
    expect(payload[:reasons]).to eq(['AMOUNT_MISMATCH'])
  end

  it 'AC-P73-10 orphan_entry：有账行但当前事实不可证（金额 0 → AMBIGUOUS）' do
    dispute = make_dispute(funds_withdrawn_at: Time.current, amount: 0)
    raw_entry(dispute, entry_type: 'DISPUTE_FUNDS_WITHDRAWN', amount: -10)

    payload = reconcile(dispute)

    expect(payload[:classification]).to eq('orphan_entry')
    expect(payload[:reasons]).to eq(['ORPHAN_ENTRY', 'fact_status_not_confirmed'])
  end

  it 'AC-P73-10 not_applicable：非现金事实且无账行（无入账义务）' do
    payload = reconcile(make_dispute)

    expect(payload[:classification]).to eq('not_applicable')
    expect(payload[:reasons]).to eq(['NO_CASH_FACT'])
    expect(payload[:skip_reason]).to eq('entry_type_not_activated')
  end

  it 'AC-P73-10 只读：对账前后零写入（行数与时间戳不变）' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)
    PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute)
    entries_before = PallasTrade::FinancialLedgerEntry.order(:id).pluck(:id, :amount, :state)
    dispute_before = dispute.reload.attributes

    reconcile(dispute)

    expect(PallasTrade::FinancialLedgerEntry.order(:id).pluck(:id, :amount, :state)).to eq(entries_before)
    expect(dispute.reload.attributes).to eq(dispute_before)
  end
end
