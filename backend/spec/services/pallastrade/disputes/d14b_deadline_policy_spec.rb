# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14b-dispute-deadlines（切片2，core 策略）
#   AC-001 ← FR-001：策略归一化矩阵（默认 / 非法回落 / 显式开启 / 档位解析）+ 分档计算
RSpec.describe PallasTrade::Disputes::DeadlinePolicy, type: :service do
  let(:store) { @default_store }

  def policy_for(raw)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Disputes::DeadlinePolicy::KEY => raw
    ))
    store.reload
    described_class.for(store)
  end

  # AC-001
  it 'defaults to T-3 / T-1 with overdue auto-lose OFF when nothing is configured' do
    policy = described_class.new

    expect(policy.tiers_days).to eq([3, 1])
    expect(policy.tiers).to eq(%w[t3 t1])
    expect(policy.auto_lose_on_overdue?).to be(false)
    expect(policy.auto_lose_limit).to eq(100)
    expect(policy.max_window_hours).to eq(72)
    expect(policy.snapshot).to include('tiers_days' => [3, 1], 'auto_lose_on_overdue' => false)
  end

  # AC-001（保守：配置错误绝不静默放行，也绝不变成「无档位 = 不提醒」）
  it 'falls back to the default tiers and a safe limit when the configuration is unusable' do
    expect(described_class.new(raw: { 'tiers_days' => [] }).tiers_days).to eq([3, 1])
    expect(described_class.new(raw: { 'tiers_days' => %w[abc -2] }).tiers_days).to eq([3, 1])
    expect(described_class.new(raw: { 'tiers_days' => '7, 3 , 1' }).tiers_days).to eq([7, 3, 1])
    expect(described_class.new(raw: { 'auto_lose_limit' => 0 }).auto_lose_limit).to eq(100)
    expect(described_class.new(raw: { 'auto_lose_limit' => 'nope' }).auto_lose_limit).to eq(100)
    expect(described_class.new(raw: { 'auto_lose_on_overdue' => 'off' }).auto_lose_on_overdue?).to be(false)
    expect(described_class.new(raw: { 'auto_lose_on_overdue' => 'true' }).auto_lose_on_overdue?).to be(true)
  end

  # AC-001
  it 'reads the store scoped policy and reports no reason to write anything' do
    before_metadata = store.private_metadata
    policy = policy_for('enabled' => true, 'tiers_days' => [5, 1], 'auto_lose_on_overdue' => true,
                        'auto_lose_limit' => 7)
    metadata_after = store.reload.private_metadata

    expect(policy.tiers_days).to eq([5, 1])
    expect(policy.auto_lose_on_overdue?).to be(true)
    expect(policy.auto_lose_limit).to eq(7)
    expect(policy.max_window_hours).to eq(120)
    expect(metadata_after[PallasTrade::Disputes::DeadlinePolicy::KEY]).to eq(before_metadata.merge(
      PallasTrade::Disputes::DeadlinePolicy::KEY => { 'enabled' => true, 'tiers_days' => [5, 1],
                                                      'auto_lose_on_overdue' => true, 'auto_lose_limit' => 7 }
    )[PallasTrade::Disputes::DeadlinePolicy::KEY])

    # 读取策略零写库（再次读取不改变元数据）
    expect { described_class.for(store.reload) }.not_to(change { store.reload.private_metadata })
  end

  # AC-001（分档计算）
  it 'resolves reached tiers from the hours remaining' do
    policy = described_class.new

    expect(policy.reached_tiers(hours_remaining: 100)).to eq([])
    expect(policy.reached_tiers(hours_remaining: 72)).to eq(['t3'])
    expect(policy.reached_tiers(hours_remaining: 50)).to eq(['t3'])
    expect(policy.reached_tiers(hours_remaining: 24)).to eq(%w[t3 t1])
    expect(policy.reached_tiers(hours_remaining: 0)).to eq(%w[t3 t1])
    expect(policy.reached_tiers(hours_remaining: -1)).to eq(%w[t3 t1 overdue])

    expect(policy.latest_tier(hours_remaining: 50)).to eq('t3')
    expect(policy.latest_tier(hours_remaining: 10)).to eq('t1')
    expect(policy.latest_tier(hours_remaining: -1)).to eq('overdue')
    expect(policy.latest_tier(hours_remaining: 200)).to be_nil
  end
end
