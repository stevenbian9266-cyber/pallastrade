# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13b-payout-ledger（切片2，core 服务）
#   AC-004 ← FR-004：匹配锚点唯一口径（charge → Payment#response_code / PaymentSession#external_id；
#            refund → Refund#transaction_id；fee/adjustment = provider 侧项目直接 matched）
#            + 金额容差 0.01 → matched / amount_mismatch / unmatched
#   AC-009 ← FR-007：零资金副作用
RSpec.describe PallasTrade::Reconciliations::Payouts::Match, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def payout_with_lines(*lines)
    payout = PallasTrade::Payout.create!(
      store: store, provider: 'stripe', reference: "po_#{SecureRandom.hex(4)}", currency: 'USD',
      status: 'in_transit', settled_at: Time.zone.parse('2026-09-10'), imported_at: Time.current
    )
    lines.each do |attrs|
      PallasTrade::PayoutLine.create!(
        { payout: payout, match_status: 'pending', currency: 'USD', fee_amount: 0,
          net_amount: attrs[:gross_amount] }.merge(attrs)
      )
    end
    payout
  end

  # 每笔支付必须有独立订单（同一订单的支付总额受订单金额上限约束）
  def payment_for(amount, response_code)
    own_order = create(:order, store: store, state: 'pending', status: 'placed',
                             item_total: amount, total: amount, payment_state: 'balance_due')
    create(:payment, order: own_order, amount: amount, state: 'completed', response_code: response_code)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-004
  it 'matches charge lines by response_code and flags amount mismatches within tolerance' do
    exact = payment_for(100, 'ch_exact')
    tolerance = payment_for(100.01, 'ch_tolerance')
    drifted = payment_for(40, 'ch_drifted')

    payout = payout_with_lines(
      { kind: 'charge', provider_reference: 'ch_exact', gross_amount: 100 },
      { kind: 'charge', provider_reference: 'ch_tolerance', gross_amount: 100 },
      { kind: 'charge', provider_reference: 'ch_drifted', gross_amount: 45 },
      { kind: 'charge', provider_reference: 'ch_missing', gross_amount: 10 },
      { kind: 'fee', provider_reference: 'fee_1', gross_amount: 3 },
      { kind: 'adjustment', provider_reference: 'adj_1', gross_amount: -1 }
    )

    result = described_class.call(payout: payout)

    expect(result.success?).to be(true)
    expect(result.value).to include(matched: 4, unmatched: 1, amount_mismatch: 1, status: 'difference')
    # 已对上的行写回本地外键（展示/追溯用；不改动 payment 本身）
    expect(payout.lines.find_by(provider_reference: 'ch_exact').payment_id).to eq(exact.id)
    expect(payout.lines.find_by(provider_reference: 'ch_tolerance').payment_id).to eq(tolerance.id)
    expect(payout.lines.find_by(provider_reference: 'ch_drifted').payment_id).to eq(drifted.id)
    expect(payout.lines.find_by(provider_reference: 'ch_exact').match_status).to eq('matched')

    mismatch = payout.lines.find_by(provider_reference: 'ch_drifted')
    expect(mismatch.match_status).to eq('amount_mismatch')
    expect(mismatch.match_details['difference'].to_d).to eq(-5.to_d)
    expect(mismatch.match_details['local_amount'].to_d).to eq(40.to_d)
    expect(mismatch.difference_amount.to_d).to eq(-5.to_d)

    unmatched = payout.lines.find_by(provider_reference: 'ch_missing')
    expect(unmatched.match_status).to eq('unmatched')
    expect(unmatched.match_details['reason']).to eq('local_payment_missing')
    expect(unmatched.payment_id).to be_nil
    expect(unmatched.matched_at).to be_present

    expect(payout.lines.find_by(provider_reference: 'fee_1').match_details['reason']).to eq('provider_side_item')
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-004
  it 'matches charge lines through the session external_id and refund lines through transaction_id' do
    payment_method = create(:bogus_payment_method, store: store, active: true)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'completed',
                                             amount: 70, currency: 'USD', external_id: 'pi_session_9')
    session_payment = create(:payment, order: order, payment_method: payment_method, amount: 70,
                                       state: 'completed', payment_session: session, response_code: nil,
                                       source: nil, skip_source_requirement: true)
    refund = create(:refund, payment: session_payment, amount: 25, transaction_id: 're_refund_9')

    payout = payout_with_lines(
      { kind: 'charge', provider_reference: 'pi_session_9', gross_amount: 70 },
      { kind: 'refund', provider_reference: 're_refund_9', gross_amount: 25 },
      { kind: 'refund', provider_reference: 're_missing', gross_amount: 5 }
    )

    result = described_class.call(payout: payout)

    expect(result.value).to include(matched: 2, unmatched: 1, amount_mismatch: 0, status: 'difference')
    expect(payout.lines.find_by(provider_reference: 'pi_session_9').payment_id).to eq(session_payment.id)
    refund_line = payout.lines.find_by(provider_reference: 're_refund_9')
    expect(refund_line.refund_id).to eq(refund.id)
    expect(refund_line.local_amount.to_d).to eq(25.to_d)
    expect(payout.lines.find_by(provider_reference: 're_missing').match_details['reason'])
      .to eq('local_refund_missing')
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-004
  it 'is idempotent and settles a payout once every line matches' do
    create(:payment, order: order, amount: 100, state: 'completed', response_code: 'ch_settle')
    payout = payout_with_lines({ kind: 'charge', provider_reference: 'ch_settle', gross_amount: 100 })

    first = described_class.call(payout: payout)
    expect(first.value).to include(matched: 1, unmatched: 0, amount_mismatch: 0, status: 'settled')

    second = described_class.call(payout: payout)

    expect(second.value).to include(matched: 1, unmatched: 0, amount_mismatch: 0, status: 'settled')
    expect(payout.lines.count).to eq(1)
    expect(PallasTrade::AuditLog.where(action: 'payout_matched').count).to eq(2)

    expect(described_class.call(payout: nil).error.to_s).to eq('Payout not found')
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-009（零资金副作用）
  it 'never mutates local payments, refunds or the ledger' do
    payment = create(:payment, order: order, amount: 100, state: 'completed', response_code: 'ch_noop')
    refund = create(:refund, payment: payment, amount: 10, transaction_id: 're_noop')
    payout = payout_with_lines(
      { kind: 'charge', provider_reference: 'ch_noop', gross_amount: 95 },
      { kind: 'refund', provider_reference: 're_noop', gross_amount: 10 }
    )
    before = [payment.amount.to_d, payment.state, payment.response_code, refund.amount.to_d, refund.state,
              PallasTrade::FinancialLedgerEntry.count]

    described_class.call(payout: payout)

    expect([payment.reload.amount.to_d, payment.state, payment.response_code, refund.reload.amount.to_d,
            refund.state, PallasTrade::FinancialLedgerEntry.count]).to eq(before)
    expect(payout.reload.status).to eq('difference')
  end
end
