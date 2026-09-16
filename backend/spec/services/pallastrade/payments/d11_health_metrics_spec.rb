# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d11-circuit-breaker-health（切片1，core 服务）
#   AC-002 ← FR-002：窗口健康指标（尝试/失败/失败率/平均时长/主要错误类）在空库与有数据时都正确
RSpec.describe PallasTrade::Payments::Health::Metrics, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:now) { Time.current }
  let(:order) { create(:order_with_line_items, store: store, shipment_cost: 0) }

  def build_session(status:, created_seconds_ago: 60, duration_seconds: 5, provider: payment_method)
    session = create(:bogus_payment_session, order: order, payment_method: provider, status: status)
    session.update_columns(created_at: now - created_seconds_ago,
                           updated_at: now - created_seconds_ago + duration_seconds)
    session
  end

  def build_failed_event(error_class, seconds_ago: 60)
    event = PallasTrade::PaymentWebhookEvent.create_unique(
      provider: 'stripe', provider_event_id: "evt_d11_#{SecureRandom.hex(6)}",
      payment_method_id: payment_method.id, action: 'failed'
    ).first
    event.update_columns(received_at: now - seconds_ago, last_error_class: error_class)
    event
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-002
  it 'returns zeroed metrics on an empty window without raising' do
    metrics = described_class.call(payment_method: payment_method, now: now)

    expect(metrics).to include(attempts: 0, failed: 0, failure_rate: 0.0, avg_seconds: nil)
    expect(metrics[:top_error_codes]).to eq([])
    expect(metrics[:window]).to eq(24.hours.inspect)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-002
  it 'aggregates attempts, failures, failure rate and average terminal duration' do
    build_session(status: 'completed', created_seconds_ago: 3600, duration_seconds: 4)
    build_session(status: 'failed', created_seconds_ago: 1800, duration_seconds: 8)
    build_session(status: 'failed', created_seconds_ago: 600, duration_seconds: 2)
    build_session(status: 'pending', created_seconds_ago: 120)
    build_session(status: 'expired', created_seconds_ago: 90, duration_seconds: 10)
    build_session(status: 'failed', created_seconds_ago: 3.days.to_i, duration_seconds: 1)

    metrics = described_class.call(payment_method: payment_method, now: now)

    expect(metrics[:attempts]).to eq(5)
    expect(metrics[:failed]).to eq(2)
    expect(metrics[:failure_rate]).to eq(0.4)
    expect(metrics[:by_status]).to include('completed' => 1, 'failed' => 2, 'pending' => 1, 'expired' => 1)
    # 终态 4 条：(4 + 8 + 2 + 10) / 4
    expect(metrics[:avg_seconds]).to eq(6.0)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-002
  it 'ignores sessions from other providers and counts only inbound failed events' do
    other = create(:bogus_payment_method, store: store, active: true, display_on: 'both')
    build_session(status: 'failed', provider: other)
    build_session(status: 'failed')
    build_failed_event('PallasTrade::Payments::ProviderTimeout')
    build_failed_event('PallasTrade::Payments::ProviderTimeout')
    build_failed_event('PallasTrade::Payments::CardDeclined')

    metrics = described_class.call(payment_method: payment_method, now: now)

    expect(metrics[:attempts]).to eq(1)
    expect(metrics[:top_error_codes]).to eq([
      { 'code' => 'PallasTrade::Payments::ProviderTimeout', 'count' => 2 },
      { 'code' => 'PallasTrade::Payments::CardDeclined', 'count' => 1 }
    ])
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-002
  it 'caps the error code list and survives providers without any data' do
    6.times { |index| build_failed_event("Err::#{index}") }

    metrics = described_class.call(payment_method: payment_method, now: now)

    expect(metrics[:top_error_codes].size).to eq(5)
    expect(metrics[:top_error_codes].first['code']).to eq('Err::0')
    expect(metrics[:top_error_codes].map { |entry| entry['code'] }).not_to include('Err::5')
  end
end
