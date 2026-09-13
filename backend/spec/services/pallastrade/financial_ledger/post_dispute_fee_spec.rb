# frozen_string_literal: true

require 'rails_helper'

# PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics
# AC-P79-05/06 —— 手续费**独立入账**（DISPUTE_FEE，负数、永不冲销）+ 幂等 + 与扣款条目分离。
RSpec.describe PallasTrade::FinancialLedger::PostDispute, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100) }

  def make_dispute(fee_amount: 15.0, withdrawn: true, reinstated: false, state: 'lost')
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p79p_#{SecureRandom.hex(4)}",
      state: state,
      amount: 12.34,
      currency: 'usd',
      # 裁决为 CONFIRMED 的前提：本地状态与 provider 状态一致（否则 PostDispute 门禁 skip）
      private_metadata: { 'provider_status' => state },
      fee_amount: fee_amount,
      funds_withdrawn_at: withdrawn ? Time.current.change(usec: 0) - 1.hour : nil,
      funds_reinstated_at: reinstated ? Time.current.change(usec: 0) : nil,
      commerce_transaction: txn,
      payment: payment
    )
  end

  it 'AC-P79-05 fee → 恰好 1 条 DISPUTE_FEE（负数、dispute 溯源、生效时间 = 扣款时间戳）' do
    dispute = make_dispute

    result = described_class.call(dispute: dispute, fact_type: 'DISPUTE_FEE')

    expect(result).to be_success
    payload = result.value
    expect(payload[:skipped]).to be(false)

    entry = payload[:entry]
    expect(entry.entry_type).to eq('DISPUTE_FEE')
    expect(entry.amount.to_d).to eq(-15.0.to_d)
    expect(entry.currency.to_s.upcase).to eq('USD')
    expect(entry.dispute).to eq(dispute)
    expect(entry.effective_at).to eq(dispute.funds_withdrawn_at)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FEE').count).to eq(1)
  end

  it 'AC-P79-05 fee 条目与扣款条目**分离**（不同 idempotency_key，各自恰好一条）' do
    dispute = make_dispute

    fee = described_class.call(dispute: dispute, fact_type: 'DISPUTE_FEE').value[:entry]
    withdrawn = described_class.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_WITHDRAWN').value[:entry]

    expect(fee.idempotency_key).not_to eq(withdrawn.idempotency_key)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FEE').count).to eq(1)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FUNDS_WITHDRAWN').count).to eq(1)
  end

  it 'AC-P79-05 幂等：重复入账不产生第二条 fee 条目' do
    dispute = make_dispute

    2.times { described_class.call(dispute: dispute, fact_type: 'DISPUTE_FEE') }

    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FEE').count).to eq(1)
  end

  it 'AC-P79-05 fee 缺失 → skip（amount_or_currency_missing，不猜金额）' do
    dispute = make_dispute(fee_amount: nil)

    result = described_class.call(dispute: dispute, fact_type: 'DISPUTE_FEE')

    expect(result.value[:skipped]).to be(true)
    expect(result.value[:reason]).to eq('amount_or_currency_missing')
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FEE').count).to eq(0)
  end

  it 'AC-P79-05 无扣款时间戳 → skip（effective_at_missing：幂等键无法稳定派生）' do
    dispute = make_dispute(withdrawn: false)

    result = described_class.call(dispute: dispute, fact_type: 'DISPUTE_FEE')

    expect(result.value[:skipped]).to be(true)
    expect(result.value[:reason]).to eq('effective_at_missing')
  end

  it 'AC-P79-06 胜诉：返还争议额但**手续费不冲销**（fee 净损失）' do
    dispute = make_dispute(state: 'won', reinstated: true)

    described_class.call(dispute: dispute, fact_type: 'DISPUTE_FEE')
    described_class.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_REINSTATED')

    fee_entry = PallasTrade::FinancialLedgerEntry.find_by(entry_type: 'DISPUTE_FEE')
    reinstated_entry = PallasTrade::FinancialLedgerEntry.find_by(entry_type: 'DISPUTE_FUNDS_REINSTATED')

    expect(fee_entry.state).to eq('posted')
    expect(fee_entry.reversed_at).to be_nil
    expect(reinstated_entry.amount.to_d).to eq(12.34.to_d)
    expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FEE').count).to eq(1)
  end

  it 'AC-P79-06 铁律：手续费入账不触碰 Payment / Order / Inventory' do
    dispute = make_dispute
    payment_state = payment.reload.attributes
    order_state = order.reload.attributes

    described_class.call(dispute: dispute, fact_type: 'DISPUTE_FEE')

    expect(payment.reload.attributes).to eq(payment_state)
    expect(order.reload.attributes).to eq(order_state)
  end
end
