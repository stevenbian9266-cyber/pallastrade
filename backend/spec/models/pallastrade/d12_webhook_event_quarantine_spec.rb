# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d12-webhook-governance（切片1，core）
#   AC-001 ← FR-001：隔离状态（quarantined + 理由 + 时间）→ 不可重放；可解除隔离；人工标记已处理
#   AC-002 ← FR-002：筛选 scope（provider / action / status / 时间窗 / 订单号）
RSpec.describe PallasTrade::PaymentWebhookEvent, type: :model do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }

  def build_event(provider_event_id: 'evt_1', action: 'captured', provider: 'stripe', **attrs)
    described_class.create_unique(
      provider: provider, provider_event_id: provider_event_id,
      payment_method_id: payment_method.id, action: action, **attrs
    ).first
  end

  # PRD-20260915-payments-d12-webhook-governance AC-001
  it 'quarantines an event with a reason and blocks replay' do
    event = build_event
    expect(event.replayable?).to be(true)

    expect(event.mark_quarantined!(reason: 'unknown event type')).to be(true)

    event.reload
    expect(event.status).to eq('quarantined')
    expect(event.quarantined_at).to be_present
    expect(event.quarantine_reason).to eq('unknown event type')
    expect(event.replayable?).to be(false)
    expect(event.quarantined?).to be(true)
  end

  # PRD-20260915-payments-d12-webhook-governance AC-001
  it 'refuses to quarantine an event that is being processed' do
    event = build_event
    event.mark_processing!

    expect(event.mark_quarantined!(reason: 'nope')).to be(false)
    expect(event.reload.status).to eq('processing')
  end

  # PRD-20260915-payments-d12-webhook-governance AC-001
  it 'unquarantines back to failed so the event can be handled again' do
    event = build_event
    event.mark_quarantined!(reason: 'triage')

    expect(event.unquarantine!).to be(true)
    event.reload
    expect(event.status).to eq('failed')
    expect(event.quarantined_at).to be_nil
    expect(event.quarantine_reason).to be_nil
    expect(event.replayable?).to be(true)
  end

  # PRD-20260915-payments-d12-webhook-governance AC-001
  it 'marks an event processed manually and clears prior errors' do
    event = build_event
    event.mark_failed!(StandardError.new('boom'))

    expect(event.mark_processed_manually!).to be(true)

    event.reload
    expect(event.status).to eq('processed')
    expect(event.processed_at).to be_present
    expect(event.last_error_message).to be_nil
  end

  # PRD-20260915-payments-d12-webhook-governance AC-002
  it 'filters by provider, action, status and received-at window' do
    keep = build_event(provider_event_id: 'evt_keep', action: 'captured')
    build_event(provider_event_id: 'evt_other_provider', action: 'captured', provider: 'adyen')
    build_event(provider_event_id: 'evt_other_action', action: 'failed')
    stale = build_event(provider_event_id: 'evt_stale')
    stale.update_columns(received_at: 40.days.ago)

    since = 7.days.ago
    expect(described_class.filter_by(provider: 'stripe', action: 'captured', from: since))
      .to contain_exactly(keep)
    expect(described_class.filter_by(status: 'received', from: since).count).to eq(3)
    expect(described_class.filter_by(to: 30.days.ago)).to contain_exactly(stale)
  end

  # PRD-20260915-payments-d12-webhook-governance AC-002
  it 'filters by order number through the payment session' do
    order = create(:order_with_line_items, store: store)
    session = create(:bogus_payment_session, order: order)
    linked = build_event(provider_event_id: 'evt_linked', payment_session_id: session.id)
    build_event(provider_event_id: 'evt_unlinked')

    expect(described_class.filter_by(order_number: order.number)).to contain_exactly(linked)
    expect(described_class.filter_by(order_number: 'R000000000')).to be_empty
  end

  # PRD-20260915-payments-d12-webhook-governance AC-002
  it 'exposes order and processing duration for the detail page' do
    order = create(:order_with_line_items, store: store)
    session = create(:bogus_payment_session, order: order)
    event = build_event(provider_event_id: 'evt_duration', payment_session_id: session.id)

    expect(event.order).to eq(order)
    expect(event.processing_duration_seconds).to be_nil

    event.update_columns(processed_at: event.received_at + 2.5)
    expect(event.reload.processing_duration_seconds).to eq(2.5)
  end
end
