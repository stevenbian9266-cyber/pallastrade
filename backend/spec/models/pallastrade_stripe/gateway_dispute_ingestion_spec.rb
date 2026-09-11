# frozen_string_literal: true

require 'rails_helper'
require 'stripe'

# PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion AC-002
# Stripe 网关的 dispute 事件接入：订阅清单 + 动作映射 + parse 分流（不要求 payment_session）。
RSpec.describe PallasTradeStripe::Gateway, type: :model do
  subject(:gateway) { create(:stripe_gateway) }

  def stripe_event(type:, object:)
    Stripe::Event.construct_from(
      id: "evt_#{SecureRandom.hex(4)}",
      type: type,
      created: Time.current.to_i,
      data: { object: object }
    )
  end

  def dispute_object(**overrides)
    {
      id: 'dp_parse_1', object: 'dispute', amount: 2500, currency: 'usd',
      status: 'needs_response', payment_intent: 'pi_parse_1', charge: 'ch_parse_1'
    }.merge(overrides)
  end

  describe '订阅清单与动作映射（AC-002）' do
    it 'subscribes the five dispute events' do
      expect(PallasTradeStripe::Config[:supported_webhook_events]).to include(
        'charge.dispute.created',
        'charge.dispute.updated',
        'charge.dispute.closed',
        'charge.dispute.funds_withdrawn',
        'charge.dispute.funds_reinstated'
      )
    end

    it 'maps them to dispute actions' do
      expect(described_class::WEBHOOK_EVENT_ACTIONS).to include(
        'charge.dispute.created' => :dispute_created,
        'charge.dispute.updated' => :dispute_updated,
        'charge.dispute.closed' => :dispute_closed,
        'charge.dispute.funds_withdrawn' => :dispute_funds_withdrawn,
        'charge.dispute.funds_reinstated' => :dispute_funds_reinstated
      )
    end
  end

  describe '#parse_webhook_event 分流（AC-002）' do
    it 'returns a dispute result without requiring a payment session' do
      allow(gateway).to receive(:verify_webhook_signature).and_return(stripe_event(type: 'charge.dispute.created', object: dispute_object))

      result = gateway.parse_webhook_event('{}', {})

      expect(result[:action]).to eq(:dispute_created)
      expect(result[:payment_session]).to be_nil
      expect(result[:metadata][:stripe_event].type).to eq('charge.dispute.created')
    end

    it 'still returns nil for unmapped event types' do
      allow(gateway).to receive(:verify_webhook_signature).and_return(stripe_event(type: 'charge.unknown_event', object: { id: 'ch_x' }))

      expect(gateway.parse_webhook_event('{}', {})).to be_nil
    end

    it 'keeps the payment path unchanged (unresolvable session → nil)' do
      event = stripe_event(type: 'payment_intent.succeeded', object: { id: 'pi_unresolvable' })
      allow(gateway).to receive(:verify_webhook_signature).and_return(event)
      # 不触网：session 解析走本地查询，找不到即 nil（与线上行为一致）
      allow(gateway).to receive(:find_session_by_payment_intent).and_return(nil)

      expect(gateway.parse_webhook_event('{}', {})).to be_nil
    end
  end
end
