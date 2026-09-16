# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14-refund-approval（切片1，core 服务）
#   AC-001 ← FR-001：策略读取与归一化的**确定性矩阵**（未配置/未启用/阈值缺失/非法/币种限定）
#   AC-009 ← FR-007：读策略零写库（不改 store、不写审计）
RSpec.describe PallasTrade::Refunds::Policy, type: :service do
  let(:store) { @default_store }

  def policy_for(config)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge('refund_policy' => config)) if config
    described_class.for(store.reload)
  end

  # PRD-20260916-payments-d14-refund-approval AC-001
  it 'is disabled when nothing is configured (behaviour stays as today)' do
    store.update_columns(private_metadata: (store.private_metadata || {}).except('refund_policy'))
    policy = described_class.for(store.reload)

    expect(policy.enabled?).to be(false)
    expect(policy.reason).to eq('disabled')
    expect(policy.requires_approval?(amount: 5_000, currency: 'USD')).to be(false)
    expect(policy.snapshot).to include('enabled' => false, 'reason' => 'disabled')
  end

  # PRD-20260916-payments-d14-refund-approval AC-001
  it 'treats an explicit false / junk enabled flag as disabled' do
    expect(policy_for({ 'enabled' => false, 'auto_approve_limit' => '10' }).enabled?).to be(false)
    expect(policy_for({ 'enabled' => 'nope', 'auto_approve_limit' => '10' }).enabled?).to be(false)
    # 非 Hash（字符串/数组）→ 不启用，不炸
    expect(policy_for('junk').enabled?).to be(false)
  end

  # PRD-20260916-payments-d14-refund-approval AC-001 / AC-002 / AC-003
  it 'approves at the limit, requires approval above it, and applies only to its currency' do
    policy = policy_for({ 'enabled' => true, 'auto_approve_limit' => '100', 'currency' => 'usd' })

    expect(policy.enabled?).to be(true)
    expect(policy.reason).to eq('ok')
    expect(policy.auto_approve_limit).to eq(BigDecimal('100'))
    expect(policy.currency).to eq('USD')

    expect(policy.requires_approval?(amount: 100, currency: 'USD')).to be(false)
    expect(policy.requires_approval?(amount: '99.99', currency: 'USD')).to be(false)
    expect(policy.requires_approval?(amount: 100.01, currency: 'USD')).to be(true)
    expect(policy.auto_approves?(amount: 50, currency: 'USD')).to be(true)

    # 币种不在策略范围 → 策略不适用（不需要审批）
    expect(policy.applies_to_currency?('EUR')).to be(false)
    expect(policy.requires_approval?(amount: 1_000, currency: 'EUR')).to be(false)
  end

  # PRD-20260916-payments-d14-refund-approval AC-001
  it 'is conservative when the limit is missing or invalid (everything needs approval)' do
    missing = policy_for({ 'enabled' => true })
    expect(missing.enabled?).to be(true)
    expect(missing.auto_approve_limit).to eq(BigDecimal('0'))
    expect(missing.reason).to eq('limit_missing_conservative')
    expect(missing.requires_approval?(amount: 0.01, currency: 'USD')).to be(true)

    blank = policy_for({ 'enabled' => true, 'auto_approve_limit' => '   ' })
    expect(blank.reason).to eq('limit_missing_conservative')

    invalid = policy_for({ 'enabled' => true, 'auto_approve_limit' => 'abc' })
    expect(invalid.auto_approve_limit).to eq(BigDecimal('0'))
    expect(invalid.reason).to eq('invalid_limit')
    expect(invalid.requires_approval?(amount: 1, currency: 'USD')).to be(true)

    negative = policy_for({ 'enabled' => true, 'auto_approve_limit' => '-5' })
    expect(negative.auto_approve_limit).to eq(BigDecimal('0'))
    expect(negative.reason).to eq('invalid_limit')
  end

  # PRD-20260916-payments-d14-refund-approval AC-001
  it 'accepts comma separated limits and falls back to nil store metadata safely' do
    policy = policy_for({ 'enabled' => true, 'auto_approve_limit' => '1,250.50' })

    expect(policy.auto_approve_limit).to eq(BigDecimal('1250.50'))
    expect(policy.requires_approval?(amount: 1_250.50, currency: 'USD')).to be(false)
    expect(policy.requires_approval?(amount: 1_250.51, currency: 'USD')).to be(true)

    expect(described_class.for(nil).enabled?).to be(false)
    expect(described_class.for(Object.new).enabled?).to be(false)
  end

  # PRD-20260916-payments-d14-refund-approval AC-009（读策略零写库）
  it 'never writes anything while reading the policy' do
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      'refund_policy' => { 'enabled' => true, 'auto_approve_limit' => '10' }
    ))
    before = store.reload.private_metadata

    described_class.for(store).requires_approval?(amount: 999, currency: 'USD')

    expect(store.reload.private_metadata).to eq(before)
    expect(PallasTrade::AuditLog.where(action: 'refund_policy_updated').count).to eq(0)
  end
end
