# frozen_string_literal: true

require 'rails_helper'

# PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics
# AC-P79-11 —— 同一支付多争议隔离：各自账行、互不覆盖；同秒乱序事件不产生重复/丢账。
RSpec.describe 'Multi-dispute isolation (DSP-P7-9)', type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100) }
  let(:same_second) { Time.zone.parse('2026-09-13 10:00:00') }

  def make_dispute(reference:, amount:, fee_amount: nil)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: reference,
      state: 'lost',
      amount: amount,
      currency: 'usd',
      # 裁决为 CONFIRMED 的前提：本地状态与 provider 状态一致
      private_metadata: { 'provider_status' => 'lost' },
      fee_amount: fee_amount,
      funds_withdrawn_at: same_second,
      commerce_transaction: txn,
      payment: payment
    )
  end

  it 'AC-P79-11 同秒同额的两笔争议各自获得独立账行（不被静默去重）' do
    first = make_dispute(reference: 'dp_multi_a', amount: 20)
    second = make_dispute(reference: 'dp_multi_b', amount: 20)

    described_class_first = PallasTrade::FinancialLedger::PostDispute.call(
      dispute: first, fact_type: 'DISPUTE_FUNDS_WITHDRAWN'
    )
    described_class_second = PallasTrade::FinancialLedger::PostDispute.call(
      dispute: second, fact_type: 'DISPUTE_FUNDS_WITHDRAWN'
    )

    expect(described_class_first.value[:skipped]).to be(false)
    expect(described_class_second.value[:skipped]).to be(false)
    expect(described_class_first.value[:entry].idempotency_key).not_to eq(
      described_class_second.value[:entry].idempotency_key
    )
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FUNDS_WITHDRAWN').count).to eq(2)
    expect(PallasTrade::FinancialLedgerEntry.where(dispute_id: first.id).count).to eq(1)
    expect(PallasTrade::FinancialLedgerEntry.where(dispute_id: second.id).count).to eq(1)
  end

  it 'AC-P79-11 两笔争议的手续费条目也各自独立' do
    first = make_dispute(reference: 'dp_multi_c', amount: 20, fee_amount: 15)
    second = make_dispute(reference: 'dp_multi_d', amount: 30, fee_amount: 15)

    PallasTrade::FinancialLedger::PostDispute.call(dispute: first, fact_type: 'DISPUTE_FEE')
    PallasTrade::FinancialLedger::PostDispute.call(dispute: second, fact_type: 'DISPUTE_FEE')

    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FEE').count).to eq(2)
    expect(PallasTrade::FinancialLedgerEntry.where(dispute_id: first.id).map(&:entry_type)).to eq(['DISPUTE_FEE'])
    expect(PallasTrade::FinancialLedgerEntry.where(dispute_id: second.id).map(&:entry_type)).to eq(['DISPUTE_FEE'])
  end

  it 'AC-P79-11 乱序事件重放（撤款→返还→撤款）不覆盖既有事实、不重复入账' do
    dispute = make_dispute(reference: 'dp_multi_e', amount: 25, fee_amount: 15)

    PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_WITHDRAWN')
    dispute.update!(funds_reinstated_at: same_second + 3.seconds, state: 'won', outcome: 'won')
    PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_REINSTATED')
    # 迟到的 funds_withdrawn 事件重放
    PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_WITHDRAWN')

    expect(PallasTrade::FinancialLedgerEntry.where(dispute_id: dispute.id).count).to eq(2)
    expect(dispute.reload.funds_withdrawn_at).to eq(same_second)
    expect(dispute.state).to eq('won')
  end
end
