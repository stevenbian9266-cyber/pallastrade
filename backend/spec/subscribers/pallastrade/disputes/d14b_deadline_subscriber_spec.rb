# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14b-dispute-deadlines（切片2，subscriber）
#   AC-003 ← FR-005：分档事件 `dispute.evidence_deadline_tier`
#            —— t3/t1 仅审计（零状态改动）；overdue 升级 `attention_reason`（不覆盖非空）
#            —— 既有 `dispute.evidence_due_soon` / `dispute.evidence_overdue` 语义回归
RSpec.describe PallasTrade::Disputes::DeadlineAlertSubscriber, type: :subscriber do
  # 事件桩：**匿名 Struct**（不定义顶层常量）——
  # 既有 legacy spec（deadline_alert_subscriber_spec.rb）已定义同形 `EventStub`；
  # RSpec example group 是块，块内常量落在顶层 → 重定义会打印
  # "previous definition of EventStub" 告警，且顶层常量会跨 spec 文件泄漏/覆盖。
  def event(name, payload)
    Struct.new(:name, :payload).new(name, payload)
  end

  let(:store) { @default_store }
  let(:dispute) do
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_d14bsub_#{SecureRandom.hex(4)}",
      state: 'needs_response', amount: 12.34, currency: 'usd', store: store,
      private_metadata: { 'provider_status' => 'needs_response' },
      evidence_due_at: Time.current + 10.hours
    )
  end
  let(:subscriber) { described_class.new }

  # AC-003（t3/t1：只留痕）
  it 'audits a tier reminder without changing the dispute state' do
    subscriber.handle(event('dispute.evidence_deadline_tier',
                            { 'id' => dispute.prefixed_id, 'tier' => 't3', 'hours_remaining' => 60.0 }))

    dispute.reload
    expect(dispute.state).to eq('needs_response')
    expect(dispute.attention_reason).to be_nil
    audit = PallasTrade::AuditLog.find_by(action: 'dispute_deadline_tier_alerted')
    expect(audit).to be_present
    expect(audit.after['tier']).to eq('t3')
    expect(audit.after['kind']).to eq('tier')
  end

  # AC-003（overdue 档：升级 attention）
  it 'escalates the overdue tier and never overwrites a more specific reason' do
    subscriber.handle(event('dispute.evidence_deadline_tier',
                            { 'id' => dispute.prefixed_id, 'tier' => 'overdue', 'hours_remaining' => -2.0 }))
    expect(dispute.reload.attention_reason).to eq('evidence_overdue')

    other = PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_d14bsub2_#{SecureRandom.hex(4)}",
      state: 'needs_response', amount: 5, currency: 'usd', store: store,
      attention_reason: 'provider_conflict', evidence_due_at: Time.current - 1.hour
    )
    subscriber.handle(event('dispute.evidence_deadline_tier',
                            { 'id' => other.prefixed_id, 'tier' => 'overdue', 'hours_remaining' => -1.0 }))
    expect(other.reload.attention_reason).to eq('provider_conflict')
  end

  # AC-003（终态 no-op + 既有事件语义回归）
  it 'ignores terminal disputes and keeps the legacy due_soon behaviour (audit only)' do
    terminal = PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_d14bsub3_#{SecureRandom.hex(4)}",
      state: 'won', amount: 5, currency: 'usd', store: store, evidence_due_at: Time.current + 2.hours
    )
    subscriber.handle(event('dispute.evidence_deadline_tier',
                            { 'id' => terminal.prefixed_id, 'tier' => 't3', 'hours_remaining' => 2.0 }))
    expect(terminal.reload.attention_reason).to be_nil
    expect(PallasTrade::AuditLog.where(resource_id: terminal.id,
                                       action: 'dispute_deadline_tier_alerted').count).to eq(0)

    subscriber.handle(event('dispute.evidence_due_soon',
                            { 'id' => dispute.prefixed_id, 'hours_remaining' => 30.0 }))
    expect(dispute.reload.state).to eq('needs_response')
    expect(dispute.attention_reason).to be_nil
    expect(PallasTrade::AuditLog.where(action: 'dispute_deadline_alerted').count).to eq(1)
  end
end
