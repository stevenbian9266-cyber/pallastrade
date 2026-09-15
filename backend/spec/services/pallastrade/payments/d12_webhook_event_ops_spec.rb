# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d12-webhook-governance（切片2，core 服务）
#   AC-003 ← FR-003：隔离 / 人工标记 各自写 Audit + 状态流转；重放复用既有链（此处断言服务契约）
RSpec.describe 'D12 webhook event ops', type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }

  def build_event(provider_event_id: 'evt_ops', action: 'captured')
    PallasTrade::PaymentWebhookEvent.create_unique(
      provider: 'stripe', provider_event_id: provider_event_id,
      payment_method_id: payment_method.id, action: action
    ).first
  end

  # PRD-20260915-payments-d12-webhook-governance AC-003
  it 'quarantines through the service and records an audit entry' do
    event = build_event

    result = PallasTrade::Payments::QuarantineWebhookEvent.call(
      webhook_event: event, reason: 'unknown event type', actor: 'ops@example.com'
    )

    expect(result.success?).to be(true)
    expect(event.reload.status).to eq('quarantined')

    audit = PallasTrade::AuditLog.where(action: 'webhook_quarantine').last
    expect(audit).to be_present
    expect(audit.resource_id).to eq(event.id)
    expect(audit.after['reason']).to eq('unknown event type')
    expect(audit.actor_label.presence || audit.actor_type).to be_present
  end

  # PRD-20260915-payments-d12-webhook-governance AC-003
  it 'rejects quarantine without a reason and leaves the event untouched' do
    event = build_event

    result = PallasTrade::Payments::QuarantineWebhookEvent.call(webhook_event: event, reason: '  ')

    expect(result.success?).to be(false)
    expect(event.reload.status).to eq('received')
    expect(PallasTrade::AuditLog.where(action: 'webhook_quarantine').count).to eq(0)
  end

  # PRD-20260915-payments-d12-webhook-governance AC-003
  it 'marks an event processed manually with an audit entry carrying the note' do
    event = build_event

    result = PallasTrade::Payments::MarkWebhookEventProcessed.call(
      webhook_event: event, actor: 'ops@example.com', note: 'refund confirmed in provider dashboard'
    )

    expect(result.success?).to be(true)
    expect(event.reload.status).to eq('processed')

    audit = PallasTrade::AuditLog.where(action: 'webhook_mark_processed').last
    expect(audit).to be_present
    expect(audit.after['note']).to eq('refund confirmed in provider dashboard')
  end

  # PRD-20260915-payments-d12-webhook-governance AC-003
  it 'refuses to mark an event processed while it is processing' do
    event = build_event
    event.mark_processing!

    result = PallasTrade::Payments::MarkWebhookEventProcessed.call(webhook_event: event)

    expect(result.success?).to be(false)
    expect(event.reload.status).to eq('processing')
  end

  # PRD-20260915-payments-d12-webhook-governance AC-003
  it 'keeps the existing replay contract: quarantined events are not replayable' do
    event = build_event
    PallasTrade::Payments::QuarantineWebhookEvent.call(webhook_event: event, reason: 'triage')

    result = PallasTrade::Payments::ReplayWebhookEvent.call(webhook_event: event.reload)

    expect(result.success?).to be(false)
  end
end
