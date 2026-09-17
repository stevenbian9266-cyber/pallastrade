# frozen_string_literal: true

# PRD-20260917-payments-d3-risk-dashboard-threshold-alerts AC-009 / AC-010 / AC-012
# 告警留痕（审计即台账）+ 事件 + 幂等 / 同日不降档 / 零副作用
require 'rails_helper'

RSpec.describe PallasTrade::Risk::DashboardAlert, type: :service do
  # 每例独占店铺：`@default_store` 是跨 example 复用的 Ruby 对象，写 metadata 容易吃到"同值不写"的坑
  let(:store) { create(:store, code: "d3_alert_#{SecureRandom.hex(4)}", default: false) }

  def configure_policy(target: store, metrics: nil, window_days: 30)
    raw = metrics || { 'review_queue_duration' => { 'enabled' => '1', 'warning' => 60, 'critical' => 120 } }
    policy, = PallasTrade::Risk::DashboardPolicy.storable(raw: { 'window_days' => window_days, 'metrics' => raw })
    target.update_columns(
      private_metadata: (target.private_metadata || {}).merge(PallasTrade::Risk::DashboardPolicy::KEY => policy.raw)
    )
    target.reload
  end

  def manual_review_transaction(wait_minutes:, target: store)
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
    PallasTrade::AuditLog.where(action: described_class::AUDIT_ACTION,
                                resource_type: described_class::RESOURCE_TYPE,
                                resource_id: target.id)
  end

  describe 'AC-009 档位进入 / 升级 → 一条审计 + 一次事件（载荷无 PII）' do
    it 'records exactly one audit row and publishes one PII-free event' do
      configure_policy
      manual_review_transaction(wait_minutes: 90) # 90 >= warning 60, < critical 120 → approaching

      allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
      allow(PallasTrade::Events).to receive(:publish)

      outcome = described_class.call(store: store)

      expect(outcome).to be_success
      expect(outcome.value[:alerts].size).to eq(1)
      expect(outcome.value[:recorded].size).to eq(1)
      expect(alerts_of(store).count).to eq(1)

      audit = alerts_of(store).first
      expect(audit.metadata.to_h).to include('metric' => 'review_queue_duration', 'status' => 'approaching',
                                             'warning' => 60, 'critical' => 120)
      expect(audit.after.to_h['status']).to eq('approaching')
      expect(PallasTrade::Events).to have_received(:publish).with(
        described_class::EVENT_NAME,
        hash_including(:store_id, :metric, :status, :value, :warning, :critical)
      ).once
    end

    it 'publishes a payload without customer identifiers' do
      configure_policy
      manual_review_transaction(wait_minutes: 200) # >= critical → breached

      allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
      allow(PallasTrade::Events).to receive(:publish)
      described_class.call(store: store)

      payload = nil
      expect(PallasTrade::Events).to have_received(:publish) { |_name, data| payload = data }
      expect(payload.keys.map(&:to_s)).to all(satisfy { |key| %w[store_id metric status value unit warning critical window_days evaluated_at].include?(key) })
    end

    it 'records nothing when the metric is not configured (no verdict, no noise)' do
      configure_policy(metrics: { 'review_queue_duration' => { 'enabled' => '0' } })
      manual_review_transaction(wait_minutes: 500)

      outcome = described_class.call(store: store)

      expect(outcome.value[:alerts]).to eq([])
      expect(alerts_of(store).count).to eq(0)
    end
  end

  describe 'AC-010 幂等 / 同日不降档 / 跨店隔离' do
    it 'does not record twice for the same metric and tier on the same day' do
      configure_policy
      manual_review_transaction(wait_minutes: 200)

      first = described_class.call(store: store)
      second = described_class.call(store: store)

      expect(first.value[:recorded].size).to eq(1)
      expect(second.value[:recorded]).to eq([])
      expect(second.value[:skipped].first).to include('duplicate:review_queue_duration:breached')
      expect(alerts_of(store).count).to eq(1)
    end

    it 'never downgrades on the same day' do
      configure_policy
      tx = manual_review_transaction(wait_minutes: 200)

      described_class.call(store: store) # breached
      tx.update_columns(manual_review_at: 70.minutes.ago) # 70 → approaching

      outcome = described_class.call(store: store)

      expect(outcome.value[:recorded]).to eq([])
      expect(outcome.value[:skipped].first).to include('no_downgrade_same_day')
      expect(alerts_of(store).count).to eq(1)
    end

    it 'keeps another store out of the picture' do
      other = create(:store, code: "d3_alert_other_#{SecureRandom.hex(4)}", default: false)
      configure_policy
      configure_policy(target: other)
      manual_review_transaction(wait_minutes: 500, target: other)

      first = described_class.call(store: store)

      expect(first.value[:recorded]).to eq([])
      expect(alerts_of(store).count).to eq(0)
      expect(alerts_of(other).count).to eq(0)

      second = described_class.call(store: other)

      expect(second.value[:recorded].size).to eq(1)
      expect(alerts_of(other).count).to eq(1)
      expect(alerts_of(store).count).to eq(0)
    end

    it 'skips a degraded report instead of guessing' do
      configure_policy
      degraded = { scope: {}, policy: {}, metrics: [], evaluated_at: nil, degraded: ['report_unavailable:PG::Error'] }

      outcome = described_class.call(store: store, report: degraded)

      expect(outcome).to be_success
      expect(outcome.value[:recorded]).to eq([])
      expect(outcome.value[:skipped].first).to include('report_degraded')
      expect(alerts_of(store).count).to eq(0)
    end
  end

  describe 'AC-012 零副作用' do
    it 'leaves transactions, payments and refunds untouched' do
      configure_policy
      tx = manual_review_transaction(wait_minutes: 500)

      before = {
        tx_state: tx.state,
        txn_count: PallasTrade::CommerceTransaction.count,
        payment_count: PallasTrade::Payment.count,
        refund_count: PallasTrade::Refund.count
      }

      described_class.call(store: store)

      expect(tx.reload.state).to eq(before[:tx_state])
      expect(PallasTrade::CommerceTransaction.count).to eq(before[:txn_count])
      expect(PallasTrade::Payment.count).to eq(before[:payment_count])
      expect(PallasTrade::Refund.count).to eq(before[:refund_count])
    end

    it 'writes no payment or refund row while alerting' do
      configure_policy
      manual_review_transaction(wait_minutes: 500)

      before_payments = PallasTrade::Payment.count
      before_refunds = PallasTrade::Refund.count
      described_class.call(store: store)

      expect(PallasTrade::Payment.count).to eq(before_payments)
      expect(PallasTrade::Refund.count).to eq(before_refunds)
    end
  end
end
