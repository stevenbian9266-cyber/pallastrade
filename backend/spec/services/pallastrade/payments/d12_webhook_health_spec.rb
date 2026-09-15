# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d12-webhook-governance（切片2，core 服务）
#   AC-004 ← FR-004：入站/出站健康聚合（计数、失败率、积压、平均耗时）在空库与有数据时都正确
RSpec.describe PallasTrade::Payments::WebhookHealth, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:now) { Time.current }

  def build_event(provider_event_id:, action: 'captured', seconds_ago: 60)
    event = PallasTrade::PaymentWebhookEvent.create_unique(
      provider: 'stripe', provider_event_id: provider_event_id,
      payment_method_id: payment_method.id, action: action
    ).first
    event.update_columns(received_at: now - seconds_ago)
    event
  end

  # PRD-20260915-payments-d12-webhook-governance AC-004
  it 'returns zeroed inbound/outbound metrics on an empty window without raising' do
    health = described_class.call(now: now)

    expect(health[:inbound]).to include(total: 0, backlog: 0, failure_rate: 0.0, avg_processing_seconds: nil)
    expect(health[:outbound]).to include(total: 0, succeeded: 0, failed: 0, backlog: 0, success_rate: 0.0)
  end

  # PRD-20260915-payments-d12-webhook-governance AC-004
  it 'aggregates inbound statuses, backlog, failure rate and average processing time' do
    processed = build_event(provider_event_id: 'evt_ok', seconds_ago: 120)
    processed.update_columns(status: 'processed', processed_at: processed.received_at + 2)
    failed = build_event(provider_event_id: 'evt_fail', seconds_ago: 90)
    failed.update_columns(status: 'failed', processed_at: failed.received_at + 4)
    build_event(provider_event_id: 'evt_received', seconds_ago: 30)
    quarantined = build_event(provider_event_id: 'evt_quarantined', seconds_ago: 20)
    quarantined.update_columns(status: 'quarantined', quarantined_at: now)
    build_event(provider_event_id: 'evt_old', seconds_ago: 3.days.to_i)

    inbound = described_class.call(now: now)[:inbound]

    expect(inbound[:total]).to eq(4)
    expect(inbound[:by_status]).to include('processed' => 1, 'failed' => 1, 'received' => 1, 'quarantined' => 1)
    expect(inbound[:backlog]).to eq(1)
    expect(inbound[:quarantined]).to eq(1)
    expect(inbound[:failure_rate]).to eq(0.5)
    expect(inbound[:avg_processing_seconds]).to eq(3.0)
    expect(inbound[:last_failure_at]).to be_present
  end

  # PRD-20260915-payments-d12-webhook-governance AC-004
  it 'aggregates outbound deliveries (success / failure / backlog)' do
    endpoint = create(:webhook_endpoint, store: store)
    create(:webhook_delivery, webhook_endpoint: endpoint, success: true)
    create(:webhook_delivery, webhook_endpoint: endpoint, success: false, delivered_at: 10.minutes.ago)
    create(:webhook_delivery, webhook_endpoint: endpoint, success: nil)

    outbound = described_class.call(now: Time.current)[:outbound]

    expect(outbound[:total]).to eq(3)
    expect(outbound[:succeeded]).to eq(1)
    expect(outbound[:failed]).to eq(1)
    expect(outbound[:backlog]).to eq(1)
    expect(outbound[:success_rate]).to eq(0.5)
    expect(outbound[:last_failure_at]).to be_present
  end
end
