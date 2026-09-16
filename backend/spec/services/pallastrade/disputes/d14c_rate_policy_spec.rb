# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14c-dispute-rate-board AC-001（阈值策略归一化 + 状态判定唯一口径）
RSpec.describe PallasTrade::Disputes::RatePolicy, type: :service do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) do
    create(:store, code: "d14c_policy_#{suffix}", default_currency: 'USD', supported_currencies: 'USD,EUR')
  end

  def policy_for(raw)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      described_class::KEY => raw
    ))
    described_class.for(store.reload)
  end

  describe 'defaults' do
    # AC-001
    it 'defaults to enabled / 30 days / 0.8 warning ratio and no configured network' do
      policy = described_class.new

      expect(policy.enabled?).to be(true)
      expect(policy.window_days).to eq(30)
      expect(policy.warning_ratio).to eq(0.8)
      expect(policy.networks).to eq({})
      expect(policy.configured_networks).to eq([])
      expect(policy.thresholds_for('visa')).to be_nil
    end
  end

  describe 'normalization' do
    # AC-001（配置错误绝不静默放行：窗口/预警比回默认，阈值非法视为未配置）
    it 'falls back to safe defaults on unusable configuration' do
      expect(policy_for({ 'window_days' => 'abc' }).window_days).to eq(30)
      expect(policy_for({ 'window_days' => 0 }).window_days).to eq(30)
      expect(policy_for({ 'window_days' => -5 }).window_days).to eq(30)
      expect(policy_for({ 'warning_ratio' => 'nope' }).warning_ratio).to eq(0.8)
      expect(policy_for({ 'warning_ratio' => 0.1 }).warning_ratio).to eq(0.8)
      expect(policy_for({ 'warning_ratio' => 3 }).warning_ratio).to eq(0.8)
    end

    # AC-001
    it 'clamps an oversized window and accepts explicit disable' do
      expect(policy_for({ 'window_days' => 9_999 }).window_days).to eq(365)
      expect(policy_for({ 'enabled' => false }).enabled?).to be(false)
      expect(policy_for({ 'enabled' => 'off' }).enabled?).to be(false)
      expect(policy_for({ 'enabled' => 'true' }).enabled?).to be(true)
    end

    # AC-001（阈值非法 → 该指标未配置，不猜数字；单边配置保留另一侧）
    it 'drops invalid thresholds and keeps one-sided configuration' do
      policy = policy_for(
        'networks' => {
          'visa' => { 'count_bps' => 65, 'amount_bps' => 90 },
          'master' => { 'count_bps' => 0, 'amount_bps' => 'x' },
          'amex' => { 'count_bps' => 20_000 },
          'VISA' => { 'count_bps' => 65 },
          'broken' => 'not-a-hash',
          'no-metrics' => { 'count_bps' => nil }
        }
      )

      expect(policy.configured_networks).to eq(%w[visa])
      expect(policy.thresholds_for('visa')).to eq(count_bps: 65, amount_bps: 90)
      expect(policy.thresholds_for('master')).to be_nil
      expect(policy.thresholds_for('amex')).to be_nil
      expect(policy.thresholds_for('broken')).to be_nil
      expect(policy.thresholds_for('no-metrics')).to be_nil
      expect(policy.thresholds_for(nil)).to be_nil
    end

    # AC-001
    it 'returns an empty network map when the value is not a hash' do
      expect(policy_for({ 'networks' => 'visa' }).networks).to eq({})
      expect(policy_for({ 'networks' => [] }).networks).to eq({})
    end
  end

  describe 'classify' do
    let(:policy) do
      policy_for('warning_ratio' => 0.8, 'networks' => { 'visa' => { 'count_bps' => 100, 'amount_bps' => 50 } })
    end

    # AC-005
    it 'is unconfigured (never judged) when the network has no threshold' do
      decision = policy.classify(network: 'master', count_ratio: 0.9, amount_ratio: 0.9)

      expect(decision[:status]).to eq('unconfigured')
      expect(decision[:triggered_metrics]).to eq([])
      expect(decision[:count_threshold_bps]).to be_nil
    end

    # AC-005（80% = 80 bps 触发 approaching；100 bps 触发 breached）
    it 'classifies ok / approaching / breached on the count metric' do
      expect(policy.classify(network: 'visa', count_ratio: 0.0079)[:status]).to eq('ok')
      expect(policy.classify(network: 'visa', count_ratio: 0.008)[:status]).to eq('approaching')
      expect(policy.classify(network: 'visa', count_ratio: 0.0099)[:status]).to eq('approaching')
      expect(policy.classify(network: 'visa', count_ratio: 0.01)[:status]).to eq('breached')
    end

    # AC-005（双阈值：只标注真正触发的那一项）
    it 'reports which metric triggered on a dual-threshold decision' do
      count_only = policy.classify(network: 'visa', count_ratio: 0.01, amount_ratio: 0.001)
      expect(count_only[:status]).to eq('breached')
      expect(count_only[:triggered_metrics]).to eq(['count'])

      amount_only = policy.classify(network: 'visa', count_ratio: 0.0001, amount_ratio: 0.005)
      expect(amount_only[:status]).to eq('breached')
      expect(amount_only[:triggered_metrics]).to eq(['amount'])

      both = policy.classify(network: 'visa', count_ratio: 0.01, amount_ratio: 0.005)
      expect(both[:triggered_metrics]).to contain_exactly('count', 'amount')
    end

    # AC-002（分母为 0 → 比率为 nil；nil 绝不触发判定）
    it 'never triggers on a nil ratio' do
      decision = policy.classify(network: 'visa', count_ratio: nil, amount_ratio: nil)

      expect(decision[:status]).to eq('ok')
      expect(decision[:triggered_metrics]).to eq([])
      expect(decision[:count_bps]).to be_nil
    end
  end

  describe 'suggested template' do
    # AC-013（建议模板默认不生效，必须显式应用）
    it 'exposes a suggested template without applying it' do
      expect(described_class.suggested_networks).to include('visa', 'master')
      expect(described_class.suggested_source_note).to be_present
      expect(described_class.new.networks).to eq({})
    end

    it 'returns a copy so callers cannot mutate the constant' do
      copy = described_class.suggested_networks
      copy['visa']['count_bps'] = 9_999

      expect(described_class::SUGGESTED['visa']['count_bps']).to eq(65)
    end
  end
end
