# frozen_string_literal: true

require 'rails_helper'

# P0-2 (PRD FR-020/FR-022): WebhookEventStore —— 验签后事件落库 + DB 级去重判定。
RSpec.describe PallasTrade::Payments::WebhookEventStore, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true) }

  # 模拟 gateway parse_webhook_event 的 metadata：{ stripe_event: <obj> }
  FakeProviderEvent = Struct.new(:id, :type, :created) do
    def to_json(*)
      { id: id, type: type, created: created }.to_json
    end
  end

  def parse_result(provider_event:, action: :captured, payment_session: nil)
    { action: action, payment_session: payment_session, metadata: { stripe_event: provider_event } }
  end

  it 'persists a received event from the provider event metadata' do
    provider_event = FakeProviderEvent.new('evt_100', 'payment_intent.succeeded', 1_700_000_000)

    event, duplicate = described_class.record(payment_method, parse_result(provider_event: provider_event))

    expect(duplicate).to be false
    expect(event).to be_persisted
    expect(event.status).to eq('received')
    expect(event.provider).to eq('bogus')
    expect(event.provider_event_id).to eq('evt_100')
    expect(event.event_type).to eq('payment_intent.succeeded')
    expect(event.action).to eq('captured')
    expect(event.provider_created_at.to_i).to eq(1_700_000_000)
    expect(event.payload).to be_present
  end

  it 'persists payment_session_id when the session is known' do
    order = create(:order_with_line_items, store: store, user: create(:user), shipment_cost: 0, line_items_price: 100)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current)
    PallasTrade::OrderUpdater.new(order).update
    session = create(:bogus_payment_session, order: order, payment_method: payment_method, amount: order.total, status: 'pending')

    provider_event = FakeProviderEvent.new('evt_101', 'payment_intent.succeeded', 1_700_000_001)
    event, = described_class.record(payment_method, parse_result(provider_event: provider_event, payment_session: session))

    expect(event.payment_session_id).to eq(session.id)
  end

  it 'returns duplicate=true and does not create a second row for the same provider_event_id' do
    provider_event = FakeProviderEvent.new('evt_102', 'payment_intent.succeeded', 1_700_000_002)

    first, = described_class.record(payment_method, parse_result(provider_event: provider_event))
    second, duplicate = described_class.record(payment_method, parse_result(provider_event: provider_event))

    expect(duplicate).to be true
    expect(second.id).to eq(first.id)
    expect(PallasTrade::PaymentWebhookEvent.count).to eq(1)
  end

  it 'returns [nil, false] when metadata has no provider event object (legacy fallback)' do
    event, duplicate = described_class.record(payment_method, parse_result(provider_event: nil))

    expect(event).to be_nil
    expect(duplicate).to be false
    expect(PallasTrade::PaymentWebhookEvent.count).to eq(0)
  end

  it 'returns [nil, false] when the provider event object has no id' do
    provider_event = FakeProviderEvent.new(nil, 'payment_intent.succeeded', 1_700_000_003)

    event, duplicate = described_class.record(payment_method, parse_result(provider_event: provider_event))

    expect(event).to be_nil
    expect(duplicate).to be false
  end
end
