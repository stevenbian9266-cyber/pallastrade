# frozen_string_literal: true

require 'rails_helper'

# P0-2 (PRD FR-023/FR-024): HandleWebhookJob —— 事件生命周期外壳。
#   - 成功 → mark_processed!
#   - 业务确定性失败（服务返回 failure）→ mark_failed! 不 raise（Manual Replay）
#   - 未知/transient 异常 → mark_failed! + raise（Job framework retry）
# PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion AC-003（dispute 动作分流到 dispute 服务，支付动作走旧服务）
# PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion AC-008（回归：既有 webhook 链路行为不变）
RSpec.describe PallasTrade::Payments::HandleWebhookJob, type: :job do
  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true) }

  # 标准流程订单（state=pending）：Carts::Submit 产物
  def pending_standard_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0, line_items_price: 100)
    order.update_columns(
      state: 'pending', status: 'placed', submitted_at: Time.current,
      completed_at: nil, payment_state: nil, payment_total: 0
    )
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def received_event(session:, action: 'canceled', provider_event_id: 'evt_job_1')
    event, = PallasTrade::PaymentWebhookEvent.create_unique(
      provider: 'bogus',
      provider_event_id: provider_event_id,
      payment_method_id: payment_method.id,
      payment_session_id: session&.id,
      action: action
    )
    event
  end

  describe 'with webhook_event_id (P0-2 path)' do
    it 'marks the event processed after a successful cancel' do
      order = pending_standard_order
      session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                               amount: order.total, status: 'pending')
      event = received_event(session: session)

      expect { described_class.perform_now(webhook_event_id: event.id) }
        .not_to raise_error

      expect(event.reload).to be_processed
      expect(session.reload).to be_canceled
    end

    it 'marks the event processed after a successful capture (full payment flow)' do
      order = pending_standard_order
      session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                               amount: order.total, status: 'pending')
      event = received_event(session: session, action: 'captured', provider_event_id: 'evt_job_2')

      described_class.perform_now(webhook_event_id: event.id)

      expect(event.reload).to be_processed
      expect(session.reload).to be_completed
      expect(order.reload).to be_completed
      expect(order.payments.count).to eq(1)
    end

    it 'marks the event failed (no raise) when the service returns a business failure' do
      fake = Class.new do
        def self.call(**)
          PallasTrade::ServiceModule::Result.new(false, nil,
                                                 PallasTrade::ServiceModule::ResultError.new('order canceled'))
        end
      end
      stub_const('PallasTrade::Payments::HandleWebhook', fake)

      event = received_event(session: nil, action: 'canceled', provider_event_id: 'evt_job_3')

      expect { described_class.perform_now(webhook_event_id: event.id) }.not_to raise_error

      expect(event.reload).to be_failed
      expect(event.last_error_message).to include('order canceled')
    end

    it 'marks the event failed and re-raises on non-retryable exception' do
      fake = Class.new do
        def self.call(**)
          raise 'unexpected infrastructure error'
        end
      end
      stub_const('PallasTrade::Payments::HandleWebhook', fake)

      event = received_event(session: nil, action: 'canceled', provider_event_id: 'evt_job_4')

      expect { described_class.perform_now(webhook_event_id: event.id) }
        .to raise_error(RuntimeError, 'unexpected infrastructure error')

      expect(event.reload).to be_failed
      expect(event.last_error_class).to eq('RuntimeError')
      expect(event.attempt_count).to eq(1)
    end
  end

  # PRD-20260911-payments-dsp-p7-1 (DSP-P7-1) AC-003：dispute 事件族分流
  describe 'dispute routing (P7-1)' do
    # 把服务常量替换为记录调用的替身（便于断言"走了哪个服务"，不依赖 RSpec 方法可见性校验）
    def stub_service(class_name, recorder)
      fake = Class.new do
        define_singleton_method(:call) do |**kwargs|
          recorder << kwargs
          PallasTrade::ServiceModule::Result.new(true, kwargs[:webhook_event], nil)
        end
      end
      stub_const(class_name, fake)
    end

    def dispute_event(action: 'dispute_created', provider_event_id: 'evt_dispute_job_1')
      payload = {
        'id' => provider_event_id,
        'type' => 'charge.dispute.created',
        'created' => Time.current.to_i,
        'data' => {
          'object' => {
            'id' => 'dp_job_1', 'object' => 'dispute', 'amount' => 500, 'currency' => 'usd',
            'status' => 'needs_response', 'reason' => 'fraudulent',
            'payment_intent' => 'pi_unknown', 'charge' => 'ch_job_1',
            'evidence_details' => { 'due_by' => (Time.current + 3.days).to_i }
          }
        }
      }
      event, = PallasTrade::PaymentWebhookEvent.create_unique(
        provider: 'stripe',
        provider_event_id: provider_event_id,
        payment_method_id: payment_method.id,
        action: action,
        event_type: payload['type'],
        payload: payload.to_json
      )
      event
    end

    it 'routes dispute actions to the dispute service (not the payment service)' do
      payment_calls = []
      stub_service('PallasTrade::Payments::HandleWebhook', payment_calls)

      event = dispute_event

      described_class.perform_now(webhook_event_id: event.id)

      expect(event.reload).to be_processed
      expect(PallasTrade::Dispute.find_by(provider_dispute_reference: 'dp_job_1')).to be_present
      expect(payment_calls).to be_empty
    end

    it 'still routes payment actions to the payment service' do
      payment_calls = []
      stub_service('PallasTrade::Payments::HandleWebhook', payment_calls)

      order = pending_standard_order
      session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                               amount: order.total, status: 'pending')
      event = received_event(session: session, action: 'canceled', provider_event_id: 'evt_job_mix')

      described_class.perform_now(webhook_event_id: event.id)

      expect(payment_calls.size).to eq(1)
      expect(event.reload).to be_processed
      expect(PallasTrade::Dispute.count).to eq(0)
    end
  end
end
