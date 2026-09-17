# frozen_string_literal: true

# PRD-20260917-payments-d3-risk-dashboard-threshold-alerts AC-001 / AC-002 / AC-003
# 策略（读 fail-safe / 写拒绝式）—— 单位：比率 bps、时长 minutes
require 'rails_helper'

RSpec.describe PallasTrade::Risk::DashboardPolicy, type: :service do
  let(:store) { @default_store }

  def metric_keys
    described_class.metric_keys
  end

  describe 'AC-001 未配置店铺 → 默认策略（零异常）' do
    it 'returns documented defaults' do
      policy = described_class.for(store)

      expect(policy.window_days).to eq(30)
      expect(policy.reasons).to eq([])
      expect(metric_keys.size).to eq(5)
      expect(policy.enabled?('dispute_rate')).to be(true)
      expect(policy.enabled?('review_queue_duration')).to be(true)
      expect(policy.enabled?('refund_rate')).to be(false)
      expect(policy.threshold_for('dispute_rate')).to eq(warning: 65, critical: 100)
    end

    it 'treats a store with no metadata as unconfigured (verdicts stay off)' do
      policy = described_class.for(store)

      expect(metric_keys).to all(satisfy { |key| policy.configured?(key) == false })
    end

    it 'never raises for a nil store' do
      expect { described_class.for(nil) }.not_to raise_error
      expect(described_class.for(nil).window_days).to eq(30)
    end
  end

  describe 'AC-002 写路径拒绝式（非法值不落库）' do
    it 'rejects an unknown metric key' do
      _policy, errors = described_class.storable(raw: { 'metrics' => { 'made_up_metric' => { 'warning' => 1, 'critical' => 2 } } })

      expect(errors.map { |e| e[:code] }).to include('unknown_metric')
    end

    it 'rejects warning >= critical' do
      _policy, errors = described_class.storable(raw: { 'metrics' => { 'dispute_rate' => { 'warning' => 200, 'critical' => 100 } } })

      expect(errors.map { |e| e[:code] }).to include('warning_not_below_critical')
    end

    it 'rejects out-of-range ratio (bps > 10000) and duration (minutes > 10080)' do
      _policy, ratio_errors = described_class.storable(raw: { 'metrics' => { 'refund_rate' => { 'warning' => 10_001, 'critical' => 20_000 } } })
      _policy2, duration_errors = described_class.storable(raw: { 'metrics' => { 'review_queue_duration' => { 'warning' => 10_081, 'critical' => 20_000 } } })

      expect(ratio_errors.map { |e| e[:code] }).to include('out_of_range')
      expect(duration_errors.map { |e| e[:code] }).to include('out_of_range')
    end

    it 'rejects an out-of-range window and a non-integer threshold' do
      _policy, window_errors = described_class.storable(raw: { 'window_days' => 0 })
      _policy2, type_errors = described_class.storable(raw: { 'metrics' => { 'refund_rate' => { 'warning' => 'abc', 'critical' => 10 } } })

      expect(window_errors.map { |e| e[:code] }).to include('out_of_range')
      expect(type_errors.map { |e| e[:code] }).to include('out_of_range')
    end
  end

  describe 'AC-003 合法保存往返一致' do
    it 'round-trips raw payload back through the reader' do
      policy, errors = described_class.storable(raw: {
        'window_days' => 60,
        'metrics' => {
          'refund_rate' => { 'enabled' => '1', 'warning' => 500, 'critical' => 900 },
          'review_queue_duration' => { 'enabled' => true, 'warning' => 30, 'critical' => 90 }
        }
      })

      expect(errors).to eq([])
      expect(policy.window_days).to eq(60)
      expect(policy.configured?('refund_rate')).to be(true)
      expect(policy.threshold_for('refund_rate')).to eq(warning: 500, critical: 900)

      reread = described_class.new(raw: policy.raw)
      expect(reread.window_days).to eq(60)
      expect(reread.threshold_for('review_queue_duration')).to eq(warning: 30, critical: 90)
      expect(reread.configured?('review_queue_duration')).to be(true)
    end

    it 'normalizes checkbox-style enabled values' do
      policy = described_class.new(raw: { 'metrics' => { 'refund_rate' => { 'enabled' => '0', 'warning' => 1, 'critical' => 2 } } })

      expect(policy.enabled?('refund_rate')).to be(false)
    end
  end

  describe '读路径 fail-safe（坏配置不 500）' do
    it 'falls back to defaults and records reasons for garbage input' do
      policy = described_class.new(raw: {
        'window_days' => 'not-a-number',
        'metrics' => { 'refund_rate' => { 'warning' => 'x', 'critical' => '-5' } }
      })

      expect(policy.window_days).to eq(30)
      expect(policy.threshold_for('refund_rate')).to eq(warning: 1_000, critical: 2_000)
      expect(policy.reasons).to be_an(Array)
    end

    it 'ignores a non-hash metrics payload without raising' do
      expect { described_class.new(raw: { 'metrics' => 'nope' }) }.not_to raise_error
      expect(described_class.new(raw: { 'metrics' => 'nope' }).window_days).to eq(30)
    end
  end
end
