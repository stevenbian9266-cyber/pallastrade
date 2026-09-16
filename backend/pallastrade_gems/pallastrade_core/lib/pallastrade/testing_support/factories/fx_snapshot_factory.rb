# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot）——
# 汇率快照工厂：默认一条 pending 状态的锁汇记录（调用方通常显式关联 order）。
FactoryBot.define do
  factory :fx_snapshot, class: 'PallasTrade::FxSnapshot' do
    store
    order
    base_currency { 'USD' }
    quote_currency { 'CNY' }
    display_rate { BigDecimal('7.1') }
    up_charge_percent { 0 }
    effective_rate { BigDecimal('7.1') }
    rate_source { 'manual' }
    locked_at { Time.current }
    locked_on { 'order.submitted' }
    variance_status { 'pending' }
    occurrences { 1 }
    signals { {} }
    metadata { {} }
  end
end
