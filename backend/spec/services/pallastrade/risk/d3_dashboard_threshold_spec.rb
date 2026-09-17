# frozen_string_literal: true

# PRD-20260917-payments-d3-risk-dashboard-threshold-alerts AC-008
# 阈值判定矩阵：ok / approaching / breached / unconfigured / unavailable
require 'rails_helper'

RSpec.describe PallasTrade::Risk::DashboardThreshold, type: :service do
  def policy_with(metric, warning:, critical:)
    PallasTrade::Risk::DashboardPolicy.new(raw: {
                                            'metrics' => { metric => { 'enabled' => '1', 'warning' => warning, 'critical' => critical } }
                                          })
  end

  def metric(key, value, unit: 'bps', reason: nil)
    { key: key, value: value, unit: unit, available: value.present?, reason: reason, window: { days: 30 }, detail: {} }
  end

  describe 'AC-008 判定矩阵' do
    it 'returns ok below the warning threshold' do
      row = described_class.classify_one(metric('refund_rate', 999), policy_with('refund_rate', warning: 1_000, critical: 2_000))

      expect(row[:status]).to eq('ok')
      expect(row[:reason]).to be_nil
      expect(row[:threshold]).to eq(warning: 1_000, critical: 2_000)
    end

    it 'returns approaching exactly at the warning threshold' do
      row = described_class.classify_one(metric('refund_rate', 1_000), policy_with('refund_rate', warning: 1_000, critical: 2_000))

      expect(row[:status]).to eq('approaching')
    end

    it 'returns breached exactly at the critical threshold' do
      row = described_class.classify_one(metric('refund_rate', 2_000), policy_with('refund_rate', warning: 1_000, critical: 2_000))

      expect(row[:status]).to eq('breached')
    end

    it 'returns breached above the critical threshold' do
      row = described_class.classify_one(metric('review_queue_duration', 500, unit: 'minutes'),
                                         policy_with('review_queue_duration', warning: 120, critical: 240))

      expect(row[:status]).to eq('breached')
      expect(row[:unit]).to eq('minutes')
    end

    it 'returns unavailable when the value is nil (never invents 0)' do
      row = described_class.classify_one(metric('refund_rate', nil, reason: 'no_denominator'),
                                         policy_with('refund_rate', warning: 1_000, critical: 2_000))

      expect(row[:status]).to eq('unavailable')
      expect(row[:reason]).to eq('no_denominator')
    end

    it 'returns unconfigured when thresholds were never set' do
      row = described_class.classify_one(metric('refund_rate', 5_000), PallasTrade::Risk::DashboardPolicy.new)

      expect(row[:status]).to eq('unconfigured')
      expect(row[:reason]).to eq('thresholds_not_configured')
    end
  end

  describe '辅助语义' do
    it 'exposes severity ordering for the no-downgrade rule' do
      expect(described_class.severity('breached')).to be > described_class.severity('approaching')
      expect(described_class.severity('approaching')).to be > described_class.severity('ok')
    end

    it 'flags only approaching/breached as alerting' do
      expect(%w[approaching breached]).to all(satisfy { |status| described_class.alerting?(status) })
      expect(%w[ok unconfigured unavailable]).to all(satisfy { |status| described_class.alerting?(status) == false })
    end

    it 'classifies a whole collection' do
      policy = policy_with('refund_rate', warning: 1_000, critical: 2_000)
      rows = described_class.classify(metrics: [metric('refund_rate', 1_500)], policy: policy)

      expect(rows.size).to eq(1)
      expect(rows.first[:status]).to eq('approaching')
    end
  end
end
