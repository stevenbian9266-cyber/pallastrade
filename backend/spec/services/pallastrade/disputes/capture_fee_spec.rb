# frozen_string_literal: true

require 'rails_helper'

# PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics
# AC-P79-04 —— 手续费**首次观测写入**：只写 `fee_amount` 一列；重放不覆盖；无证据不猜。
RSpec.describe PallasTrade::Disputes::CaptureFee, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  def make_dispute(fee_amount: nil, link_payment: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p79f_#{SecureRandom.hex(4)}",
      state: 'lost',
      amount: 12.34,
      currency: 'usd',
      fee_amount: fee_amount,
      funds_withdrawn_at: Time.current.change(usec: 0),
      payment: link_payment ? payment : nil
    )
  end

  it 'AC-P79-04 provider 给出 fee → 首次观测写入（币种取 dispute 币种）' do
    dispute = make_dispute

    result = described_class.call(dispute: dispute, snapshot: { fee_amount: BigDecimal('15.0') })

    expect(result).to be_success
    expect(result.value[:recorded]).to be(true)
    expect(dispute.reload.fee_amount.to_d).to eq(15.0.to_d)
    expect(result.value[:currency].to_s.downcase).to eq('usd')
  end

  it 'AC-P79-04 重放不覆盖（已有 fee 时零写）' do
    dispute = make_dispute(fee_amount: 15.0)

    result = described_class.call(dispute: dispute, snapshot: { fee_amount: 99.0 })

    expect(result.value[:recorded]).to be(false)
    expect(dispute.reload.fee_amount.to_d).to eq(15.0.to_d)
  end

  it 'AC-P79-04 快照无 fee / fee 为 0 / fee 畸形 → 不写（不猜）' do
    [nil, 0, 'abc'].each do |raw|
      dispute = make_dispute
      result = described_class.call(dispute: dispute, snapshot: { fee_amount: raw })

      expect(result.value[:recorded]).to be(false)
      expect(dispute.reload.fee_amount).to be_nil
    end
  end

  it 'AC-P79-04 无 payment 锚点 → 降级 UNLINKED_PAYMENT 且零写' do
    dispute = make_dispute(link_payment: false)

    result = described_class.call(dispute: dispute)

    expect(result).to be_success
    expect(result.value[:degraded]).to eq('UNLINKED_PAYMENT')
    expect(dispute.reload.fee_amount).to be_nil
  end

  it 'AC-P79-04 只写 fee_amount 一列（争议状态/金额/时间戳逐字节不变）' do
    dispute = make_dispute
    snapshot = { state: dispute.state, amount: dispute.amount, funds_withdrawn_at: dispute.funds_withdrawn_at }

    described_class.call(dispute: dispute, snapshot: { fee_amount: 15.0 })

    dispute.reload
    expect(dispute.state).to eq(snapshot[:state])
    expect(dispute.amount.to_d).to eq(snapshot[:amount].to_d)
    expect(dispute.funds_withdrawn_at).to eq(snapshot[:funds_withdrawn_at])
  end
end
