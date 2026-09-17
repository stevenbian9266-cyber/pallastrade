# frozen_string_literal: true

# PRD-20260917-payments-d3-risk-dashboard-threshold-alerts AC-010 / AC-012 / AC-013
# 巡检作业：逐店隔离、单店模式、幂等、坏配置不炸、未知店铺安全
require 'rails_helper'

RSpec.describe PallasTrade::Risk::DashboardAlertSweeperJob, type: :job do
  let(:store) { create(:store, code: "d3_job_#{SecureRandom.hex(4)}", default: false) }

  def configure_policy(target:, warning: 60, critical: 120)
    policy, = PallasTrade::Risk::DashboardPolicy.storable(raw: {
      'window_days' => 30,
      'metrics' => { 'review_queue_duration' => { 'enabled' => '1', 'warning' => warning, 'critical' => critical } }
    })
    target.update_columns(
      private_metadata: (target.private_metadata || {}).merge(PallasTrade::Risk::DashboardPolicy::KEY => policy.raw)
    )
    target.reload
  end

  def manual_review_transaction(target:, wait_minutes: 500)
    tx = PallasTrade::CommerceTransaction.create!(store: target, purpose: 'purchase',
                                                  currency: target.default_currency.to_s, amount: 10)
    tx.start_payment!
    tx.confirm_payment!
    tx.mark_recovery_required!
    tx.manual_review!
    tx.update_columns(manual_review_at: wait_minutes.minutes.ago)
    tx.reload
  end

  def alerts_of(target)
    PallasTrade::AuditLog.where(action: PallasTrade::Risk::DashboardAlert::AUDIT_ACTION,
                                resource_type: PallasTrade::Risk::DashboardAlert::RESOURCE_TYPE,
                                resource_id: target.id)
  end

  describe '#perform' do
    it 'evaluates the store and reports a summary' do
      configure_policy(target: store)
      manual_review_transaction(target: store)
      allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
      allow(PallasTrade::Events).to receive(:publish)

      summary = described_class.new.perform(store_id: store.id)

      expect(summary[:evaluated]).to eq(1)
      expect(summary[:recorded]).to eq(1)
      expect(summary[:failed]).to eq(0)
      expect(alerts_of(store).count).to eq(1)
    end

    it 'scopes to a single store when store_id is given' do
      other = create(:store, code: "d3_job_other_#{SecureRandom.hex(4)}", default: false)
      configure_policy(target: other)
      manual_review_transaction(target: other)

      summary = described_class.new.perform(store_id: store.id)

      expect(summary[:evaluated]).to eq(1)
      expect(alerts_of(other).count).to eq(0)
    end

    it 'is idempotent across runs on the same day' do
      configure_policy(target: store)
      manual_review_transaction(target: store)

      first = described_class.new.perform(store_id: store.id)
      second = described_class.new.perform(store_id: store.id)

      expect(first[:recorded]).to eq(1)
      expect(second[:recorded]).to eq(0)
      expect(second[:skipped]).to be >= 1
      expect(alerts_of(store).count).to eq(1)
    end

    it 'never raises for a store with a garbage policy' do
      store.update_columns(private_metadata: { PallasTrade::Risk::DashboardPolicy::KEY => 'not-a-hash' })

      expect { described_class.new.perform(store_id: store.id) }.not_to raise_error
    end

    it 'handles an unknown store id safely' do
      summary = described_class.new.perform(store_id: 987_654_321)

      expect(summary[:evaluated]).to eq(0)
      expect(summary[:failed]).to eq(0)
    end

    it 'keeps store state untouched while sweeping' do
      configure_policy(target: store)
      tx = manual_review_transaction(target: store)

      described_class.new.perform(store_id: store.id)

      expect(tx.reload.state).to eq('manual_review')
    end
  end
end
