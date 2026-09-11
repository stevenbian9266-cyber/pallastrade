# frozen_string_literal: true

require 'rails_helper'

# PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion AC-005 AC-006 AC-007
# `PallasTrade::Disputes::HandleProviderEvent` —— dispute 事件的唯一落库入口：
#   - 事件驱动（Stripe `charge.dispute.*` 载荷）→ durable Dispute
#   - 无锚点不丢事件；重放幂等；**零业务副作用**（P7-0 B2/B3/B4/B5）
RSpec.describe PallasTrade::Disputes::HandleProviderEvent do
  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true) }

  let(:order) do
    create(:order_with_line_items, store: store, user: user, shipment_cost: 0, line_items_price: 100).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end

  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total,
                     response_code: 'pi_dispute_anchor')
  end

  def stripe_dispute_payload(**overrides)
    base = {
      dispute_id: 'dp_test_1', status: 'needs_response', amount: 1234,
      currency: 'usd', due_by: (Time.current + 5.days).to_i,
      payment_intent: 'pi_dispute_anchor', charge: 'ch_test_1',
      reason: 'fraudulent', type: 'charge.dispute.created'
    }
    values = base.merge(overrides)

    {
      'id' => "evt_#{SecureRandom.hex(4)}",
      'type' => values[:type],
      'created' => Time.current.to_i,
      'data' => {
        'object' => {
          'id' => values[:dispute_id],
          'object' => 'dispute',
          'amount' => values[:amount],
          'currency' => values[:currency],
          'status' => values[:status],
          'reason' => values[:reason],
          'payment_intent' => values[:payment_intent],
          'charge' => values[:charge],
          'evidence_details' => { 'due_by' => values[:due_by], 'has_evidence' => false }
        }
      }
    }
  end

  def webhook_event(action:, payload:, provider_event_id: "evt_#{SecureRandom.hex(4)}")
    event, = PallasTrade::PaymentWebhookEvent.create_unique(
      provider: 'stripe',
      provider_event_id: provider_event_id,
      payment_method_id: payment_method.id,
      action: action,
      event_type: payload['type'],
      payload: payload.to_json,
      provider_created_at: Time.current
    )
    event
  end

  describe 'happy path（AC-005）' do
    it 'creates a durable dispute linked to payment/order/store' do
      payment # 建立锚点
      result = described_class.call(
        webhook_event: webhook_event(action: 'dispute_created', payload: stripe_dispute_payload)
      )

      expect(result).to be_success
      dispute = PallasTrade::Dispute.find_by(provider: 'stripe', provider_dispute_reference: 'dp_test_1')

      expect(dispute).to be_present
      expect(dispute).to be_needs_response
      expect(dispute.kind).to eq('chargeback')
      expect(dispute.amount).to eq(12.34)
      expect(dispute.currency).to eq('usd')
      expect(dispute.evidence_due_at).to be_present
      expect(dispute.payment_id).to eq(payment.id)
      expect(dispute.order_id).to eq(order.id)
      expect(dispute.store_id).to eq(store.id)
      expect(dispute.provider_charge_reference).to eq('ch_test_1')
      expect(dispute.provider_payment_reference).to eq('pi_dispute_anchor')
      expect(dispute.attention_reason).to be_nil
    end

    it 'maps warning_* statuses to kind=warning' do
      payment
      described_class.call(
        webhook_event: webhook_event(action: 'dispute_created', payload: stripe_dispute_payload(status: 'warning_needs_response'))
      )

      dispute = PallasTrade::Dispute.find_by(provider_dispute_reference: 'dp_test_1')

      expect(dispute.kind).to eq('warning')
      expect(dispute).to be_needs_response
    end

    it 'keeps one row across created → updated → closed and converges state' do
      payment
      described_class.call(webhook_event: webhook_event(action: 'dispute_created', payload: stripe_dispute_payload))

      described_class.call(
        webhook_event: webhook_event(action: 'dispute_updated',
                                     payload: stripe_dispute_payload(status: 'under_review',
                                                                     type: 'charge.dispute.updated'))
      )
      described_class.call(
        webhook_event: webhook_event(action: 'dispute_closed',
                                     payload: stripe_dispute_payload(status: 'won', type: 'charge.dispute.closed'))
      )

      disputes = PallasTrade::Dispute.where(provider_dispute_reference: 'dp_test_1')

      expect(disputes.count).to eq(1)
      dispute = disputes.first
      expect(dispute).to be_won
      expect(dispute.outcome).to eq('won')
      expect(dispute.resolved_at).to be_present
    end
  end

  describe '无锚点不丢事件（AC-006）' do
    it 'persists the row and flags attention when no local payment matches' do
      result = described_class.call(
        webhook_event: webhook_event(action: 'dispute_created',
                                     payload: stripe_dispute_payload(payment_intent: 'pi_unknown'))
      )

      expect(result).to be_success
      dispute = PallasTrade::Dispute.find_by(provider_dispute_reference: 'dp_test_1')

      expect(dispute).to be_present
      expect(dispute.payment_id).to be_nil
      expect(dispute.attention_reason).to eq('unlinked_payment')
      expect(dispute).to be_attention
    end

    it 'fails loudly on malformed payloads (no dispute object)' do
      result = described_class.call(
        webhook_event: webhook_event(action: 'dispute_created', payload: { 'id' => 'evt_x', 'data' => {} })
      )

      expect(result).to be_failure
      expect(PallasTrade::Dispute.count).to eq(0)
    end
  end

  describe '零业务副作用 + 重放幂等（AC-007）' do
    it 'does not touch order / payment / inventory / ledger / refunds' do
      payment
      order_state = order.reload.state
      payment_state = payment.reload.state
      ledger_count = PallasTrade::FinancialLedgerEntry.count
      inventory_count = PallasTrade::InventoryUnit.count
      refund_count = PallasTrade::Refund.count

      described_class.call(webhook_event: webhook_event(action: 'dispute_created', payload: stripe_dispute_payload))

      expect(order.reload.state).to eq(order_state)
      expect(payment.reload.state).to eq(payment_state)
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(ledger_count)
      expect(PallasTrade::InventoryUnit.count).to eq(inventory_count)
      expect(PallasTrade::Refund.count).to eq(refund_count)
    end

    it 'is idempotent when the same event is replayed' do
      payment
      payload = stripe_dispute_payload
      event = webhook_event(action: 'dispute_created', payload: payload)

      2.times { described_class.call(webhook_event: event) }

      expect(PallasTrade::Dispute.where(provider_dispute_reference: 'dp_test_1').count).to eq(1)
    end

    it 'records invalid transitions as attention instead of raising' do
      payment
      described_class.call(
        webhook_event: webhook_event(action: 'dispute_closed',
                                     payload: stripe_dispute_payload(status: 'won', type: 'charge.dispute.closed'))
      )
      result = described_class.call(
        webhook_event: webhook_event(action: 'dispute_updated',
                                     payload: stripe_dispute_payload(status: 'needs_response',
                                                                     type: 'charge.dispute.updated'))
      )

      expect(result).to be_success
      dispute = PallasTrade::Dispute.find_by(provider_dispute_reference: 'dp_test_1')

      expect(dispute).to be_won # 终态不被回退
      expect(dispute.attention_reason).to eq('invalid_transition')
      expect(dispute.private_metadata['invalid_transition']['to']).to eq('needs_response')
    end
  end
end
