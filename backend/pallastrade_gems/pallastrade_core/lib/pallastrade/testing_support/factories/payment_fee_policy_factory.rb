# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片3（PRD-20260916-payments-d13c-fee-cost-report）——
# 费率策略工厂：默认一条「兜底」策略，测试按需覆写 scope / 条件 / 分量。
FactoryBot.define do
  factory :payment_fee_policy, class: 'PallasTrade::PaymentFeePolicy' do
    name { "Fee policy #{SecureRandom.hex(4)}" }
    scope_type { 'global' }
    status { 'active' }
    percent_fee { 2.9 }
    fixed_fee { 0.3 }
    platform_percent { 0 }
    cross_border_percent { 0 }
    cross_border_fixed { 0 }
    currency_conversion_percent { 0 }
    metadata { {} }
  end
end
