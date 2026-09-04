# frozen_string_literal: true

require 'rails_helper'

# P0-2 (PRD FR-020/FR-021/FR-022): PaymentWebhookEvent 生命周期 + DB 级去重。
RSpec.describe PallasTrade::PaymentWebhookEvent, type: :model do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true) }

  def build_event(provider_event_id: 'evt_123', action: 'captured')
    described_class.create_unique(
      provider: 'stripe',
      provider_event_id: provider_event_id,
      payment_method_id: payment_method.id,
      action: action
    )
  end

  describe '.create_unique' do
    it 'creates a received event and returns [event, false]' do
      event, duplicate = build_event

      expect(duplicate).to be false
      expect(event).to be_persisted
      expect(event.status).to eq('received')
      expect(event.received_at).to be_present
      expect(event.provider).to eq('stripe')
      expect(event.action).to eq('captured')
    end

    it 'returns the existing event with duplicate=true on repeat provider_event_id' do
      first, dup1 = build_event
      expect(dup1).to be false

      second, dup2 = build_event

      expect(dup2).to be true
      expect(second.id).to eq(first.id)
      expect(described_class.count).to eq(1)
    end

    it 'raises RecordInvalid on invalid action (schema guard)' do
      expect { build_event(action: 'mystery') }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'state machine' do
    it 'received → processing increments attempt_count and stamps processing_at' do
      event, = build_event
      expect { event.mark_processing! }.to change { event.attempt_count }.from(0).to(1)
      expect(event).to be_processing
      expect(event.processing_at).to be_present
    end

    it 'does not re-enter processing from processing' do
      event, = build_event
      event.mark_processing!
      count = event.attempt_count

      expect(event.mark_processing!).to be false
      expect(event.reload.attempt_count).to eq(count)
    end

    it 'processing → processed clears error fields' do
      event, = build_event
      event.mark_processing!
      event.update!(last_error_class: 'Boom', last_error_message: 'x')

      event.mark_processed!

      expect(event.reload).to be_processed
      expect(event.processed_at).to be_present
      expect(event.last_error_class).to be_nil
      expect(event.last_error_message).to be_nil
    end

    it 'processing → failed stores error and allows retry via mark_processing!' do
      event, = build_event
      event.mark_processing!

      event.mark_failed!(RuntimeError.new('connection lost'))

      expect(event.reload).to be_failed
      expect(event.last_error_class).to eq('RuntimeError')
      expect(event.last_error_message).to eq('connection lost')

      # failed → processing（Job retry / Manual Replay 路径）
      expect { event.mark_processing! }.to change { event.attempt_count }.by(1)
      expect(event.reload).to be_processing
    end
  end

  describe '#replayable?' do
    it 'is false while processing' do
      event, = build_event
      event.mark_processing!
      expect(event).not_to be_replayable
    end

    it 'is true from received / failed / processed' do
      expect(build_event[0]).to be_replayable

      failed, = build_event(provider_event_id: 'evt_fail')
      failed.mark_processing!
      failed.mark_failed!(RuntimeError.new('x'))
      expect(failed.reload).to be_replayable

      processed, = build_event(provider_event_id: 'evt_done')
      processed.mark_processing!
      processed.mark_processed!
      expect(processed.reload).to be_replayable
    end
  end

  describe 'provider_created_at normalization' do
    it 'converts numeric unix epoch to a Time' do
      event, = described_class.create_unique(
        provider: 'stripe',
        provider_event_id: 'evt_epoch',
        payment_method_id: payment_method.id,
        action: 'captured',
        provider_created_at: 1_700_000_000
      )

      expect(event.reload.provider_created_at).to be_a(Time)
      expect(event.provider_created_at.to_i).to eq(1_700_000_000)
    end
  end
end
