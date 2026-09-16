# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# `Currencies::Fx::Policy` —— 店铺汇率策略（存 `Store#private_metadata['fx_policy']`）的唯一读口径。
#
# 键与默认值：
#   * `enabled`（默认 `true`）—— 关闭后不再锁汇；
#   * `up_charge_percent`（默认 0）—— 加点，快照同时保留 display_rate 与 effective_rate；
#   * `variance_tolerance_bips`（默认 **50**，即 0.5%）—— 结算汇率偏差容差；
#   * `auto_reconcile`（默认 `true`）—— 超容差自动进入对账队列；
#   * `default_source`（默认 nil = 按优先级取）。
#
# 归一化：非法/越界值一律回落默认（**不猜**）；只读，不写库。
module PallasTrade
  module Currencies
    module Fx
      class Policy
        prepend PallasTrade::ServiceModule::Base

        METADATA_KEY = 'fx_policy'
        DEFAULT_UP_CHARGE_PERCENT = 0
        DEFAULT_TOLERANCE_BIPS = 50
        MAX_TOLERANCE_BIPS = 10_000
        MAX_UP_CHARGE_PERCENT = 100

        DEFAULTS = {
          enabled: true,
          up_charge_percent: DEFAULT_UP_CHARGE_PERCENT,
          variance_tolerance_bips: DEFAULT_TOLERANCE_BIPS,
          auto_reconcile: true,
          default_source: nil
        }.freeze

        # @param store [PallasTrade::Store, nil]
        # @return [PallasTrade::ServiceModule::Result] success(Hash)
        def call(store:)
          success(normalize(store))
        end

        class << self
          # 便捷读法（内部服务使用；与 `call` 同口径）
          # @return [Hash]
          def for_store(store)
            new.send(:normalize, store)
          end
        end

        private

        def normalize(store)
          raw = raw_policy(store)
          DEFAULTS.merge(
            enabled: boolean_or_default(raw['enabled'], DEFAULTS[:enabled]),
            up_charge_percent: bounded_decimal(raw['up_charge_percent'], DEFAULTS[:up_charge_percent], 0,
                                               MAX_UP_CHARGE_PERCENT),
            variance_tolerance_bips: bounded_integer(raw['variance_tolerance_bips'],
                                                     DEFAULTS[:variance_tolerance_bips], 0, MAX_TOLERANCE_BIPS),
            auto_reconcile: boolean_or_default(raw['auto_reconcile'], DEFAULTS[:auto_reconcile]),
            default_source: normalized_source(raw['default_source'])
          )
        end

        def raw_policy(store)
          metadata = store.respond_to?(:private_metadata) ? store.private_metadata : nil
          policy = metadata.is_a?(Hash) ? metadata[METADATA_KEY] : nil
          policy.is_a?(Hash) ? policy.transform_keys(&:to_s) : {}
        end

        def boolean_or_default(value, fallback)
          case value
          when true, false then value
          when 'true', 1, '1' then true
          when 'false', 0, '0' then false
          else fallback
          end
        end

        def bounded_decimal(value, fallback, min, max)
          decimal = decimal_or_nil(value)
          return fallback if decimal.nil? || decimal.negative? || decimal > max

          decimal.round(4)
        end

        def bounded_integer(value, fallback, min, max)
          decimal = decimal_or_nil(value)
          return fallback if decimal.nil? || decimal < min || decimal > max

          decimal.to_i
        end

        def decimal_or_nil(value)
          return value if value.is_a?(Numeric)
          return nil if value.blank?

          BigDecimal(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def normalized_source(value)
          source = value.to_s.strip.downcase
          PallasTrade::CurrencyRate::SOURCES.include?(source) ? source : nil
        end
      end
    end
  end
end
