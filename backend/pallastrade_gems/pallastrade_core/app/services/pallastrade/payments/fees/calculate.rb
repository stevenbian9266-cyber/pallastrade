# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片3（PRD-20260916-payments-d13c-fee-cost-report；业务方案 §70.3 费率模型）——
# `Payments::Fees::Calculate` —— **单笔费用计算**（纯函数：零写库、零 provider I/O）。
#
# 口径（唯一，测试与报表共用）：
#   * 费率类分量 `variable = 金额 × (percent_fee + platform_percent)/100`
#                       `+ 金额 × cross_border_percent/100`（**仅当判定为跨境**）
#                       `+ 金额 × currency_conversion_percent/100`（**仅当判定为需货币转换**）
#   * `variable` 应用 `min_fee` / `max_fee`（保底 / 封顶）→ `clamped`，`adjustment = clamped - variable`
#   * `fixed = fixed_fee + (跨境 ? cross_border_fixed : 0)`（固定费**不参与**保底封顶）
#   * `total_fee = clamped + fixed`；`net_amount = amount - total_fee`
#   * 跨境 / 转换的判定基准由策略声明（`home_country` / `settlement_currency`）：
#     声明了但本地拿不到对照值 → **不计费** + signal（`cross_border_undetermined` / `conversion_undetermined`），绝不臆造。
#   * 无策略（`policy` 为 nil）→ `priced = false`，`total_fee = 0`，signal `no_policy`。
module PallasTrade
  module Payments
    module Fees
      class Calculate
        prepend PallasTrade::ServiceModule::Base

        CURRENCY_PRECISION = 2

        # @param amount [Numeric, String, BigDecimal] 支付金额
        # @param currency [String] 支付币种
        # @param policy [PallasTrade::PaymentFeePolicy, nil]
        # @param order_country [String, nil] 订单账单国家 ISO（跨境判定对照值）
        # @param policy_home_country [String, nil] 覆盖策略的基准国（一般留 nil，取策略值）
        # @param settlement_currency [String, nil] 覆盖策略的基准币（一般留 nil，取策略值）
        # @return [PallasTrade::ServiceModule::Result] success(Hash)
        def call(amount:, policy:, currency: nil, order_country: nil,
                 policy_home_country: nil, settlement_currency: nil)
          amount = amount.to_d.round(CURRENCY_PRECISION)
          signals = []

          if policy.nil?
            return success(unpriced_result(amount, currency, signals + ['no_policy']))
          end

          cross_border, cross_border_signal = determine_cross_border(policy, order_country, policy_home_country)
          conversion, conversion_signal = determine_conversion(policy, currency, settlement_currency)
          signals.concat([cross_border_signal, conversion_signal].compact)

          percent_fee = round(amount * policy.percent_fee.to_d / 100)
          platform_fee = round(amount * policy.platform_percent.to_d / 100)
          cross_border_fee = cross_border ? round(amount * policy.cross_border_percent.to_d / 100) : 0.to_d
          conversion_fee = conversion ? round(amount * policy.currency_conversion_percent.to_d / 100) : 0.to_d

          variable = round(percent_fee + platform_fee + cross_border_fee + conversion_fee)
          clamped = clamp_variable(variable, policy)
          fixed = round(policy.fixed_fee.to_d + (cross_border ? policy.cross_border_fixed.to_d : 0.to_d))
          total = round(clamped + fixed)

          success({
                    priced: true,
                    policy_id: policy.id,
                    policy_name: policy.name,
                    scope_type: policy.scope_type,
                    scope_id: policy.scope_id,
                    amount: amount,
                    currency: currency.to_s.upcase.presence,
                    percent_fee: percent_fee,
                    platform_fee: platform_fee,
                    cross_border_fee: cross_border_fee,
                    conversion_fee: conversion_fee,
                    variable_fee: variable,
                    clamped_fee: clamped,
                    adjustment: round(clamped - variable),
                    fixed_fee: fixed,
                    total_fee: total,
                    net_amount: round(amount - total),
                    cross_border: cross_border,
                    converted: conversion,
                    signals: signals
                  })
        end

        private

        def unpriced_result(amount, currency, signals)
          {
            priced: false,
            policy_id: nil,
            policy_name: nil,
            scope_type: nil,
            scope_id: nil,
            amount: amount,
            currency: currency.to_s.upcase.presence,
            percent_fee: 0.to_d,
            platform_fee: 0.to_d,
            cross_border_fee: 0.to_d,
            conversion_fee: 0.to_d,
            variable_fee: 0.to_d,
            clamped_fee: 0.to_d,
            adjustment: 0.to_d,
            fixed_fee: 0.to_d,
            total_fee: 0.to_d,
            net_amount: amount,
            cross_border: false,
            converted: false,
            signals: signals
          }
        end

        # @return [Array(Boolean, String, nil)]
        def determine_cross_border(policy, order_country, policy_home_country)
          home = (policy_home_country.presence || policy.home_country.presence)
          return [false, nil] if home.blank?

          country = order_country.to_s.upcase.presence
          return [false, 'cross_border_undetermined'] if country.blank?

          [country != home.to_s.upcase, nil]
        end

        # @return [Array(Boolean, String, nil)]
        def determine_conversion(policy, currency, settlement_currency)
          settlement = (settlement_currency.presence || policy.settlement_currency.presence)
          return [false, nil] if settlement.blank?

          present = currency.to_s.upcase.presence
          return [false, 'conversion_undetermined'] if present.blank?

          [present != settlement.to_s.upcase, nil]
        end

        def clamp_variable(variable, policy)
          min = policy.min_fee.present? ? policy.min_fee.to_d : nil
          max = policy.max_fee.present? ? policy.max_fee.to_d : nil
          result = variable
          result = min if min && result < min
          result = max if max && result > max
          round(result)
        end

        def round(value)
          value.to_d.round(CURRENCY_PRECISION)
        end
      end
    end
  end
end
