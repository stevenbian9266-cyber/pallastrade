# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B2 / FR-007) AC-007 / AC-010
# —— 期限提醒与升级：due_soon 只留痕；overdue 打人工关注标记（不覆盖既有原因）；
# 终态/找不到 → no-op；异常不冒泡；**零自动化、零资金副作用**。
require 'rails_helper'

RSpec.describe PallasTrade::Disputes::DeadlineAlertSubscriber do
  let!(:store) { create(:store, code: "p710_alert_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  EventStub = Struct.new(:name, :payload)

  def make_dispute(state: 'needs_response', due_at: 1.hour.ago, attention_reason: nil)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p710alert@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p710al_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p710al_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd', evidence_due_at: due_at,
      attention_reason: attention_reason,
      store_id: store.id, payment: payment, order: order
    )
  end

  def due_soon_event(dispute, hours: 30.0)
    EventStub.new('dispute.evidence_due_soon', { 'id' => dispute.prefixed_id, 'hours_remaining' => hours })
  end

  def overdue_event(dispute, hours: -2.0)
    EventStub.new('dispute.evidence_overdue', { 'id' => dispute.prefixed_id, 'hours_remaining' => hours })
  end

  def write_counts
    {
      submissions: PallasTrade::DisputeEvidenceSubmission.count,
      approvals: PallasTrade::DisputeEvidenceApproval.count,
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count,
      inventory_units: PallasTrade::InventoryUnit.count,
      stock_reservations: PallasTrade::StockReservation.count
    }
  end

  it 'AC-007 due_soon 只留痕：审计 + 指标，不改状态、不打标记' do
    dispute = make_dispute(due_at: 30.hours.from_now)

    described_class.new.handle(due_soon_event(dispute))

    expect(PallasTrade::AuditLog.where(action: 'dispute_deadline_alerted').count).to eq(1)
    expect(dispute.reload.attention_reason).to be_nil
    expect(dispute.state).to eq('needs_response')
  end

  it 'AC-007 overdue 升级为人工关注（并记录归属原因），不覆盖既有更具体的原因' do
    overdue = make_dispute(attention_reason: nil)
    already_flagged = make_dispute(attention_reason: 'journal_gap')

    described_class.new.handle(overdue_event(overdue))
    described_class.new.handle(overdue_event(already_flagged))

    expect(overdue.reload.attention_reason).to eq('evidence_overdue')
    expect(already_flagged.reload.attention_reason).to eq('journal_gap')
    expect(PallasTrade::AuditLog.where(action: 'dispute_deadline_alerted').count).to eq(2)
  end

  it 'AC-007 终态争议与未知 id 均为 no-op（且不抛错）' do
    won = make_dispute(state: 'won')

    described_class.new.handle(overdue_event(won))
    described_class.new.handle(EventStub.new('dispute.evidence_overdue', { 'id' => 'dsp_missing' }))
    described_class.new.handle(EventStub.new('dispute.evidence_overdue', {}))

    expect(won.reload.attention_reason).to be_nil
    expect(PallasTrade::AuditLog.where(action: 'dispute_deadline_alerted').count).to eq(0)
  end

  it 'AC-007 支持 raw integer id（双模 payload）' do
    dispute = make_dispute

    described_class.new.handle(EventStub.new('dispute.evidence_overdue', { 'id' => dispute.id }))

    expect(dispute.reload.attention_reason).to eq('evidence_overdue')
  end

  it 'AC-007 异常不外抛（留痕失败也不阻断 sweeper）' do
    dispute = make_dispute
    allow(PallasTrade::Audit).to receive(:record).and_raise(StandardError, 'audit down')

    expect { described_class.new.handle(overdue_event(dispute)) }.not_to raise_error
    expect(dispute.reload.attention_reason).to eq('evidence_overdue')
  end

  it 'AC-010 铁律：提醒不产生任何资金/库存/订单/回执写，也不推进状态机' do
    dispute = make_dispute(due_at: 5.hours.from_now)
    before = write_counts

    described_class.new.handle(due_soon_event(dispute))
    described_class.new.handle(overdue_event(dispute))

    expect(write_counts).to eq(before)
    expect(dispute.reload.state).to eq('needs_response')
    expect(dispute.evidence_submitted_at).to be_nil
  end

  it 'AC-007 已注册进 PallasTrade.subscribers（否则事件静默丢失）' do
    expect(PallasTrade.subscribers).to include(described_class)
  end
end
