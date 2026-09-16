# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4）
#   AC-4 ← FR-6：店铺汇率策略归一化与默认值（enabled / up_charge / tolerance / auto_reconcile）
RSpec.describe PallasTrade::Currencies::Fx::Policy do
  def policy_for(metadata)
    store = build(:store)
    store.private_metadata = metadata
    described_class.call(store: store).value
  end

  it 'returns the documented defaults when nothing is configured' do
    result = policy_for(nil)

    expect(result[:enabled]).to be(true)
    expect(result[:up_charge_percent]).to eq(0)
    expect(result[:variance_tolerance_bips]).to eq(50)
    expect(result[:auto_reconcile]).to be(true)
    expect(result[:default_source]).to be_nil
  end

  it 'normalizes an explicit policy' do
    result = policy_for('fx_policy' => { 'enabled' => false, 'up_charge_percent' => '0.5',
                                         'variance_tolerance_bips' => 120, 'auto_reconcile' => false,
                                         'default_source' => 'PROVIDER' })

    expect(result[:enabled]).to be(false)
    expect(result[:up_charge_percent]).to eq(BigDecimal('0.5'))
    expect(result[:variance_tolerance_bips]).to eq(120)
    expect(result[:auto_reconcile]).to be(false)
    expect(result[:default_source]).to eq('provider')
  end

  it 'falls back to defaults for out-of-range or malformed values (never guesses)' do
    result = policy_for('fx_policy' => { 'up_charge_percent' => -3, 'variance_tolerance_bips' => 99_999,
                                         'enabled' => 'maybe', 'default_source' => 'friends' })

    expect(result[:enabled]).to be(true)
    expect(result[:up_charge_percent]).to eq(0)
    expect(result[:variance_tolerance_bips]).to eq(50)
    expect(result[:default_source]).to be_nil
  end

  it 'reads through the object helper as well' do
    store = build(:store)
    store.private_metadata = { 'fx_policy' => { 'up_charge_percent' => 1.25 } }

    expect(described_class.for_store(store)[:up_charge_percent]).to eq(BigDecimal('1.25'))
  end
end
