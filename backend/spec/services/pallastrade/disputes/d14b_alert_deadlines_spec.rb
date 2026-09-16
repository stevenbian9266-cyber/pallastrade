# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14b-dispute-deadlines（切片2，core 服务）
#   AC-002 ← FR-002/FR-003：分档台账幂等（达到即记、重复不重记、跳档补齐）
#   AC-003 ← FR-003：仅**新档位**发布 `dispute.evidence_deadline_tier`
#   AC-004 ← FR-004：超期自动置 lost（策略门控 + 未提交证据 + 单轮上限）
#   AC-006 ← FR-007：零资金副作用
RSpec.describe PallasTrade::Disputes::AlertDeadlines, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_price: 50, shipment_cost: 0).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total, state: 'completed',
                     response_code: 'pi_d14b_anchor', source: nil, skip_source_requirement: true)
  end
  let(:txn) do
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: order.total)
  end

  def set_policy(auto_lose: false, tiers: [3, 1], limit: 100)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Disputes::DeadlinePolicy::KEY => {
        'tiers_days' => tiers, 'auto_lose_on_overdue' => auto_lose, 'auto_lose_limit' => limit
      }
    ))
    store.reload
  end

  def make_dispute(state: 'needs_response', due_at: nil, reference: nil, submitted_at: nil)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: reference || "dp_d14b_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd', store: store,
      private_metadata: { 'provider_status' => 'needs_response' },
      evidence_due_at: due_at, evidence_submitted_at: submitted_at,
      commerce_transaction: txn, payment: payment, order: order
    )
  end

  def alerts_for(dispute)
    PallasTrade::DisputeDeadlineAlert.where(dispute_id: dispute.id).order(:tier).pluck(:tier)
  end

  # AC-002
  it 'records the reached tier once and never repeats it on the next run' do
    set_policy
    now = Time.current.change(usec: 0)
    dispute = make_dispute(due_at: now + 48.hours)

    first = described_class.call(store: store, now: now)
    expect(first.success?).to be(true)
    expect(first.value[:tiers_recorded]).to eq(1)
    expect(first.value[:alerted]).to eq(1)
    expect(alerts_for(dispute)).to eq(['t3'])
    expect(dispute.reload.deadline_alerts.pluck(:tier)).to eq(['t3'])

    alert = dispute.deadline_alerts.sole
    expect(alert.store_id).to eq(store.id)
    expect(alert.backfilled?).to be(false)
    expect(alert.metadata['policy']).to include('tiers_days' => [3, 1])

    second = described_class.call(store: store, now: now + 1.hour)
    expect(second.value[:tiers_recorded]).to eq(0)
    expect(second.value[:alerted]).to eq(0)
    expect(alerts_for(dispute)).to eq(['t3'])
    expect(PallasTrade::AuditLog.where(action: 'dispute_deadline_tier_recorded').count).to eq(1)
  end

  # AC-002
  it 'records the tighter tier when the deadline gets closer' do
    set_policy
    now = Time.current.change(usec: 0)
    dispute = make_dispute(due_at: now + 10.hours)

    described_class.call(store: store, now: now)

    expect(alerts_for(dispute)).to eq(%w[t1 t3])
    alerts = dispute.deadline_alerts.index_by(&:tier)
    # 首次扫描时 T-3 已过 → 补齐但标记 backfilled（只落台账，不补发过期提醒）
    expect(alerts['t3'].backfilled?).to be(true)
    expect(alerts['t1'].backfilled?).to be(false)
  end

  # AC-003
  it 'publishes the tier event only for the newest tier recorded in that run' do
    set_policy
    now = Time.current.change(usec: 0)
    dispute = make_dispute(due_at: now + 10.hours)
    published = []
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
    allow(PallasTrade::Events).to receive(:publish) { |name, payload| published << [name, payload] }

    described_class.call(store: store, now: now)

    tier_events = published.select { |name, _| name == 'dispute.evidence_deadline_tier' }
    expect(tier_events.size).to eq(1)
    expect(tier_events.first.last).to include('id' => dispute.prefixed_id, 'tier' => 't1')

    described_class.call(store: store, now: now + 30.minutes)
    expect(published.select { |name, _| name == 'dispute.evidence_deadline_tier' }.size).to eq(1)
  end

  # AC-002（超期档）
  it 'records the overdue tier for a dispute past its deadline' do
    set_policy
    now = Time.current.change(usec: 0)
    dispute = make_dispute(due_at: now - 5.hours, reference: 'dp_d14b_overdue')

    result = described_class.call(store: store, now: now)

    expect(result.value[:tiers_recorded]).to eq(3)
    expect(alerts_for(dispute)).to eq(%w[overdue t1 t3])
    expect(dispute.deadline_alerts.for_tier('overdue').exists?).to be(true)
  end

  # AC-004（默认关闭：只提醒，不改状态 —— 与今天一致）
  it 'keeps the dispute untouched when auto-lose is off' do
    set_policy(auto_lose: false)
    now = Time.current.change(usec: 0)
    dispute = make_dispute(due_at: now - 5.hours)

    result = described_class.call(store: store, now: now)

    expect(result.value[:auto_lost]).to eq(0)
    expect(dispute.reload.state).to eq('needs_response')
    expect(PallasTrade::AuditLog.where(action: 'dispute_auto_lost_overdue').count).to eq(0)
  end

  # AC-004（开启：超期 + 未提交证据 → lost + attention + 审计）
  it 'auto-loses an overdue dispute without evidence when the policy is on' do
    set_policy(auto_lose: true)
    now = Time.current.change(usec: 0)
    dispute = make_dispute(due_at: now - 5.hours)

    result = described_class.call(store: store, now: now)

    expect(result.value[:auto_lost]).to eq(1)
    dispute.reload
    expect(dispute.state).to eq('lost')
    expect(dispute.attention_reason).to eq('evidence_overdue')
    expect(dispute.resolved_at).to be_present

    audit = PallasTrade::AuditLog.find_by(action: 'dispute_auto_lost_overdue')
    expect(audit).to be_present
    expect(audit.after['state']).to eq('lost')

    # 幂等：再跑一次不重复置 lost（终态不再处理）
    again = described_class.call(store: store, now: now + 1.hour)
    expect(again.value[:auto_lost]).to eq(0)
    expect(PallasTrade::AuditLog.where(action: 'dispute_auto_lost_overdue').count).to eq(1)
  end

  # AC-004（已提交证据 / 终态 → 不自动置 lost）
  it 'never auto-loses a dispute that already has evidence or is terminal' do
    set_policy(auto_lose: true)
    now = Time.current.change(usec: 0)
    submitted = make_dispute(due_at: now - 3.hours, submitted_at: now - 4.hours, reference: 'dp_d14b_submitted')
    terminal = make_dispute(due_at: now - 3.hours, state: 'won', reference: 'dp_d14b_won')

    result = described_class.call(store: store, now: now)

    expect(result.value[:auto_lost]).to eq(0)
    expect(result.value[:skipped_submitted]).to eq(1)
    expect(submitted.reload.state).to eq('needs_response')
    expect(terminal.reload.state).to eq('won')
  end

  # AC-004（单轮上限）
  it 'caps the number of auto-lost disputes per run' do
    set_policy(auto_lose: true, limit: 1)
    now = Time.current.change(usec: 0)
    first = make_dispute(due_at: now - 2.hours, reference: 'dp_d14b_cap_1')
    second = make_dispute(due_at: now - 3.hours, reference: 'dp_d14b_cap_2')

    result = described_class.call(store: store, now: now)

    expect(result.value[:auto_lost]).to eq(1)
    expect([first.reload.state, second.reload.state].count('lost')).to eq(1)
  end

  # AC-006（零资金副作用）
  it 'never touches money, provider or the payment state' do
    set_policy(auto_lose: true)
    now = Time.current.change(usec: 0)
    make_dispute(due_at: now - 2.hours, reference: 'dp_d14b_money')
    before = {
      payments: PallasTrade::Payment.count, refunds: PallasTrade::Refund.count,
      ledger: PallasTrade::FinancialLedgerEntry.count, orders: PallasTrade::Order.count,
      amount: payment.reload.amount.to_d, state: payment.state,
      funds_withdrawn_at: PallasTrade::Dispute.find_by(provider_dispute_reference: 'dp_d14b_money').funds_withdrawn_at
    }

    described_class.call(store: store, now: now)

    after = {
      payments: PallasTrade::Payment.count, refunds: PallasTrade::Refund.count,
      ledger: PallasTrade::FinancialLedgerEntry.count, orders: PallasTrade::Order.count,
      amount: payment.reload.amount.to_d, state: payment.state,
      funds_withdrawn_at: PallasTrade::Dispute.find_by(provider_dispute_reference: 'dp_d14b_money').funds_withdrawn_at
    }
    expect(after).to eq(before)
  end
end
