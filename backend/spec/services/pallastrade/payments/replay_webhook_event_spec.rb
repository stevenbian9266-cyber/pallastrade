# frozen_string_literal: true

require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

# P0-2 (PRD FR-026): Payments::ReplayWebhookEvent —— Manual Replay。
#   复用原事件记录 → HandleWebhookJob 重放（attempt_count+1）→ 不制造新事件。
RSpec.describe PallasTrade::Payments::ReplayWebhookEvent, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true) }

  def failed_event(provider_event_id: 'evt_replay_1')
    event, = PallasTrade::PaymentWebhookEvent.create_unique(
      provider: 'bogus',
      provider_event_id: provider_event_id,
      payment_method_id: payment_method.id,
      action: 'canceled'
    )
    event.mark_processing!
    event.mark_failed!(RuntimeError.new('first attempt died'))
    event.reload
  end

  it 'enqueues HandleWebhookJob with the original webhook_event_id for a failed event' do
    event = failed_event
    result = nil

    expect do
      result = described_class.call(webhook_event: event, actor: 'admin@example.com')
    end.to have_enqueued_job(PallasTrade::Payments::HandleWebhookJob)
      .with(hash_including(webhook_event_id: event.id))
    expect(result).to be_success
  end

  it 'writes an audit log for the replay (P0-6 / FR-064)' do
    event = failed_event

    expect do
      described_class.call(webhook_event: event, actor: 'admin@example.com')
    end.to change(PallasTrade::AuditLog, :count).by(1)

    entry = PallasTrade::AuditLog.recent(1).first
    expect(entry.action).to eq('webhook_replay')
    expect(entry.actor_label).to eq('admin@example.com')
    expect(entry.resource_type).to eq('PallasTrade::PaymentWebhookEvent')
    expect(entry.resource_id).to eq(event.id)
    expect(entry.after).to include('provider_event_id' => event.provider_event_id)
  end

  it 'refuses to replay an event that is currently processing' do
    event, = PallasTrade::PaymentWebhookEvent.create_unique(
      provider: 'bogus',
      provider_event_id: 'evt_replay_2',
      payment_method_id: payment_method.id,
      action: 'canceled'
    )
    event.mark_processing!
    result = nil

    expect { result = described_class.call(webhook_event: event, actor: 'admin@example.com') }
      .not_to have_enqueued_job(PallasTrade::Payments::HandleWebhookJob)
    expect(result).to be_failure
  end
end
