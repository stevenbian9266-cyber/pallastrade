# frozen_string_literal: true

require 'rails_helper'

# PRD-20260908-payments-rev-p6-8f §11 (REV-P6-8k) AC-R68K-03/04:
# payment_combination.cancel_orchestrated → CombinationCancelSubscriber → Audit + OperationalMetrics
RSpec.describe PallasTrade::Orders::CombinationCancelSubscriber, type: :job do
  let(:store) { @default_store }
  let(:subscriber) { described_class.new }

  def fire(payload)
    subscriber.send(:handle, double(payload: payload))
  end

  it 'declares subscription to payment_combination.cancel_orchestrated' do
    expect(described_class.subscription_patterns).to include('payment_combination.cancel_orchestrated')
  end

  it 'AC-R68K-03: 收到事件 → Audit.record（action=payment_combination_cancel_orchestrated, after 含聚合）+ OperationalMetrics.count' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 100, status: 'succeeded')
    allow(PallasTrade::OperationalMetrics).to receive(:count)

    payload = {
      'id' => combo.prefixed_id,
      'status' => 'succeeded',
      'members' => { 'total' => 2, 'canceled' => 1, 'skipped' => 1, 'failed' => 0 },
      'canceled_order_ids' => ['ord_1'],
      'canceled_by' => 'ops@example.com'
    }

    expect { fire(payload) }
      .to change { PallasTrade::AuditLog.where(action: 'payment_combination_cancel_orchestrated').count }.by(1)

    log = PallasTrade::AuditLog.where(action: 'payment_combination_cancel_orchestrated').last
    expect(log.actor_label).to eq('ops@example.com')
    expect(log.resource_type).to eq('PallasTrade::PaymentCombination')
    expect(log.resource_prefixed_id).to eq(combo.prefixed_id)
    expect(log.after['members']).to eq('total' => 2, 'canceled' => 1, 'skipped' => 1, 'failed' => 0)
    expect(log.after['canceled_order_ids']).to eq(['ord_1'])

    expect(PallasTrade::OperationalMetrics).to have_received(:count).with(
      'payment_combination.cancel_orchestrated',
      combination_id: combo.prefixed_id,
      canceled: 1, skipped: 1, failed: 0
    )
  end

  it 'AC-R68K-03: 无 canceled_by → actor=system；payload raw integer id 亦解析' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 50, status: 'succeeded')
    allow(PallasTrade::OperationalMetrics).to receive(:count)

    fire('id' => combo.id, 'members' => { 'canceled' => 1, 'skipped' => 0, 'failed' => 0 })

    log = PallasTrade::AuditLog.where(action: 'payment_combination_cancel_orchestrated').last
    expect(log.actor_label).to eq('system')
    expect(log.resource_id).to eq(combo.id)
  end

  it 'AC-R68K-04: combination 缺失 / payload nil → 安全 no-op 不 raise' do
    allow(PallasTrade::OperationalMetrics).to receive(:count)
    expect { fire('id' => 'pcom_missing') }.not_to raise_error
    expect { fire(nil) }.not_to raise_error
    expect(PallasTrade::AuditLog.where(action: 'payment_combination_cancel_orchestrated').count).to eq(0)
  end

  it 'AC-R68K-04: Audit/OperationalMetrics 异常 → rescue 不 raise（log）' do
    combo = create(:payment_combination, store: store, currency: 'USD', amount: 10, status: 'succeeded')
    allow(PallasTrade::OperationalMetrics).to receive(:count).and_raise('boom')

    expect { fire('id' => combo.prefixed_id, 'members' => { 'canceled' => 1 }) }.not_to raise_error
  end
end
