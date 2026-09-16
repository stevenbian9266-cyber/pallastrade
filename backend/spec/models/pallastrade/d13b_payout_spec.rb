# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13b-payout-ledger（切片2，core 模型）
#   AC-001 ← FR-001/FR-002：台账状态合成（差异优先 → 已结算 → 在途）
#            + 汇总由行求和的唯一口径 + (store, provider, reference) 唯一约束
#            + 后台筛选口径（provider / status / 到账日区间）
RSpec.describe PallasTrade::Payout, type: :model do
  let(:store) { @default_store }

  def build_payout(**attrs)
    PallasTrade::Payout.create!(
      { store: store, provider: 'stripe', reference: "po_#{SecureRandom.hex(4)}",
        currency: 'USD', status: 'in_transit', imported_at: Time.current }.merge(attrs)
    )
  end

  def build_line(payout, **attrs)
    PallasTrade::PayoutLine.create!(
      { payout: payout, kind: 'charge', provider_reference: "ch_#{SecureRandom.hex(4)}",
        gross_amount: 100, fee_amount: 3, net_amount: 97, match_status: 'matched' }.merge(attrs)
    )
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-001
  it 'derives in_transit -> settled -> difference from its lines' do
    payout = build_payout
    build_line(payout)

    expect(payout.refresh_status!).to eq('in_transit')
    expect(payout.reload.status).to eq('in_transit')

    payout.update!(settled_at: Time.zone.parse('2026-09-10'))
    expect(payout.refresh_status!).to eq('settled')

    build_line(payout, kind: 'charge', match_status: 'amount_mismatch')
    expect(payout.reload.refresh_status!).to eq('difference')
    expect(payout.difference?).to be(true)
    expect(payout.difference_lines.count).to eq(1)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-001
  it 'recalculates totals from its lines and keeps them in sync' do
    payout = build_payout
    build_line(payout, gross_amount: 100, fee_amount: 3, net_amount: 97)
    build_line(payout, kind: 'refund', gross_amount: -25, fee_amount: 0, net_amount: -25)

    payout.recalculate_totals!

    expect(payout.reload.gross_total.to_d).to eq(75.to_d)
    expect(payout.fee_total.to_d).to eq(3.to_d)
    expect(payout.net_total.to_d).to eq(72.to_d)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-002
  it 'rejects a duplicate (store, provider, reference) and accepts the same reference for another provider' do
    build_payout(reference: 'po_duplicate')

    expect { build_payout(reference: 'po_duplicate') }.to raise_error(ActiveRecord::RecordInvalid)
    expect { build_payout(reference: 'po_duplicate', provider: 'adyen') }.not_to raise_error
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-001
  it 'filters by provider, status and settled date range' do
    settled = build_payout(provider: 'stripe', status: 'settled', settled_at: Time.zone.parse('2026-09-10'))
    in_transit = build_payout(provider: 'adyen', status: 'in_transit', settled_at: nil)
    older = build_payout(provider: 'stripe', status: 'difference', settled_at: Time.zone.parse('2026-08-01'))

    expect(described_class.filter_by(store_id: store.id, provider: 'stripe').pluck(:id))
      .to contain_exactly(settled.id, older.id)
    expect(described_class.filter_by(store_id: store.id, status: 'in_transit').pluck(:id)).to eq([in_transit.id])
    expect(
      described_class.filter_by(store_id: store.id, from: Time.zone.parse('2026-09-01'),
                                                 to: Time.zone.parse('2026-09-30')).pluck(:id)
    ).to eq([settled.id])
    expect(described_class.filter_by(store_id: store.id).pluck(:id))
      .to contain_exactly(settled.id, in_transit.id, older.id)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-001
  it 'treats difference lines as a difference with 0.01 tolerance and records the delta' do
    payout = build_payout
    line = build_line(payout, gross_amount: 100, match_status: 'pending')

    expect(line.difference?).to be(false)
    line.mark_match!(status: 'amount_mismatch', details: { 'difference' => '5.0' })
    expect(line.reload.difference_amount).to eq('5.0')
    expect(line.matched_at).to be_present

    line.mark_match!(status: 'pending')
    expect(line.reload.matched_at).to be_nil
    expect { line.mark_match!(status: 'exploded') }.to raise_error(ArgumentError)
  end
end
