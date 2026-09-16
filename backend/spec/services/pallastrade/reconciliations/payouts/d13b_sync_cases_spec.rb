# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13b-payout-ledger（切片2，core 服务）
#   AC-005 ← FR-005：结算差异行 → 对账队列（D13 切片1）的唯一写入口：
#            差异入队（幂等）/ 恢复 matched 自动销案 / 签名变化销旧案 / 人工判定不被覆盖
#   AC-009 ← FR-007：零资金副作用
RSpec.describe PallasTrade::Reconciliations::Payouts::SyncCases, type: :service do
  let(:store) { @default_store }

  def payout_with_line(match_status:, provider_reference: 'ch_case', kind: 'charge', gross_amount: 100)
    payout = PallasTrade::Payout.create!(
      store: store, provider: 'stripe', reference: "po_#{SecureRandom.hex(4)}", currency: 'USD',
      status: 'in_transit', settled_at: Time.zone.parse('2026-09-10'), imported_at: Time.current
    )
    PallasTrade::PayoutLine.create!(
      payout: payout, kind: kind, provider_reference: provider_reference, currency: 'USD',
      gross_amount: gross_amount, fee_amount: 0, net_amount: gross_amount, match_status: match_status,
      match_details: { 'reason' => 'local_payment_missing' }
    )
    payout
  end

  def cases_for(payout)
    PallasTrade::ReconciliationCase.where(kind: 'payout').where("dedupe_key LIKE ?", "payout:#{payout.id}:%")
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-005
  it 'opens a payout case for an unmatched line and touches it on repeat runs' do
    payout = payout_with_line(match_status: 'unmatched')

    first = described_class.call(payout: payout)

    expect(first.success?).to be(true)
    expect(first.value[:opened].size).to eq(1)
    expect(first.value[:touched]).to be_empty

    kase = cases_for(payout).sole
    expect(kase.status).to eq('open')
    expect(kase.kind).to eq('payout')
    expect(kase.difference_type).to eq('payout_unmatched')
    expect(kase.severity).to eq('attention')
    expect(kase.reason_codes).to eq(['PAYOUT_LINE_UNMATCHED'])
    expect(kase.provider).to eq('stripe')
    expect(kase.observed_amount.to_d).to eq(100.to_d)
    expect(kase.expected_amount).to be_nil
    expect(kase.summary['payout_reference']).to eq(payout.reference)
    expect(kase.summary['line_kind']).to eq('charge')
    expect(kase.metadata['payout_id']).to eq(payout.id)
    expect(kase.occurrences).to eq(1)

    second = described_class.call(payout: payout)

    expect(second.value[:touched].size).to eq(1)
    expect(second.value[:opened]).to be_empty
    expect(cases_for(payout).count).to eq(1)
    expect(kase.reload.occurrences).to eq(2)
    expect(PallasTrade::AuditLog.where(action: 'payout_cases_synced').count).to eq(2)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-005
  it 'maps an amount mismatch line to its own difference type and stores both amounts' do
    payout = payout_with_line(match_status: 'amount_mismatch')
    line = payout.lines.sole
    line.update!(match_details: { 'local_amount' => '95.0', 'provider_amount' => '100.0', 'difference' => '5.0' })

    described_class.call(payout: payout)

    kase = cases_for(payout).sole
    expect(kase.difference_type).to eq('payout_amount_mismatch')
    expect(kase.reason_codes).to eq(['PAYOUT_AMOUNT_MISMATCH'])
    expect(kase.summary['difference']).to eq('5.0')
    expect(kase.metadata['payout_line_id']).to eq(line.id)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-005
  it 'auto-closes the case once the line matches again and never overrides a human verdict' do
    payout = payout_with_line(match_status: 'unmatched')
    described_class.call(payout: payout)
    kase = cases_for(payout).sole

    payout.lines.sole.update!(match_status: 'matched', match_details: { 'reason' => 'provider_side_item' })
    result = described_class.call(payout: payout)

    expect(result.value[:closed]).to eq([kase.id])
    expect(kase.reload.status).to eq('fixed')
    expect(kase.resolution_source).to eq('auto')

    # 人工判定（explained / dismissed）永不被系统覆盖
    payout2 = payout_with_line(match_status: 'unmatched')
    described_class.call(payout: payout2)
    human = cases_for(payout2).sole
    human.update!(status: 'explained', resolution_source: 'human', resolved_at: Time.current)

    result2 = described_class.call(payout: payout2)

    expect(result2.value[:touched]).to eq([human.id])
    expect(human.reload.status).to eq('explained')
    expect(human.resolution_source).to eq('human')
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-005
  it 'supersedes the stale case when the same line changes its difference signature' do
    payout = payout_with_line(match_status: 'unmatched')
    described_class.call(payout: payout)
    stale = cases_for(payout).sole

    payout.lines.sole.update!(match_status: 'amount_mismatch')
    result = described_class.call(payout: payout)

    expect(stale.reload.status).to eq('fixed')
    expect(stale.resolution_source).to eq('auto')
    expect(result.value[:closed]).to eq([stale.id])
    expect(result.value[:opened].size).to eq(1)

    fresh = cases_for(payout).where.not(id: stale.id).sole
    expect(fresh.difference_type).to eq('payout_amount_mismatch')
    expect(fresh.status).to eq('open')
    expect(cases_for(payout).count).to eq(2)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-009（零资金副作用）
  it 'only writes the ledger and case tables plus audit' do
    payout = payout_with_line(match_status: 'unmatched')
    before = [PallasTrade::Payment.count, PallasTrade::Refund.count, PallasTrade::Order.count,
              PallasTrade::FinancialLedgerEntry.count]

    described_class.call(payout: payout)

    expect([PallasTrade::Payment.count, PallasTrade::Refund.count, PallasTrade::Order.count,
            PallasTrade::FinancialLedgerEntry.count]).to eq(before)
    expect(payout.reload.lines.sole.match_status).to eq('unmatched')
    expect(described_class.call(payout: nil).error.to_s).to eq('Payout not found')
  end
end
