# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片1（PRD-20260916-payments-d14-refund-approval；业务方案 §71.1）——
# `Refunds::Policy` —— 店铺级退款审批策略（**只读**值对象，唯一口径）。
#
# 存储：`Store#private_metadata['refund_policy']`（无新表；策略变更写审计，不写策略表）。
# 字段：
#   * `enabled`            —— 是否启用审批门（未配置 / 非真值 → **不启用** = 行为与今天一致）
#   * `auto_approve_limit` —— 金额上界：`amount <= limit` 自动执行；严格大于才需审批
#   * `currency`           —— 策略币种（空/缺失 = 适用于全部币种；不匹配 = 策略不适用）
#
# 归一化（保守 + 显式，绝不静默放行）：
#   * 未配置 / `enabled` 非真值 → `enabled? == false`，`reason = 'disabled'`
#   * `enabled` 真值但阈值缺失或非法（负数/非数值）→ 阈值按 **0**（全部需审批）+ `reason`
#     （宁可全部走审批，也不放过超阈值退款）
#   * 币种统一 upcase；空 → nil（全部币种）
#
# 铁律：读策略**零写库**、零 provider I/O。
module PallasTrade
  module Refunds
    class Policy
      KEY = 'refund_policy'
      TRUE_VALUES = [true, 'true', 1, '1', 'yes', 'on'].freeze

      attr_reader :reason

      # @param store [PallasTrade::Store, nil]
      # @return [PallasTrade::Refunds::Policy]
      def self.for(store)
        raw = store.respond_to?(:private_metadata) ? (store.private_metadata || {})[KEY] : nil
        new(raw: raw)
      end

      # @param raw [Hash, nil] 策略原始配置
      def initialize(raw: nil)
        config = raw.is_a?(Hash) ? raw : raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : nil

        @enabled = config.present? && truthy?(config['enabled'] || config[:enabled])
        @currency = normalize_currency(config && (config['currency'] || config[:currency]))
        @raw_limit = config && (config.key?('auto_approve_limit') ? config['auto_approve_limit'] : config[:auto_approve_limit])
        @auto_approve_limit, @reason = resolve_limit
      end

      def enabled?
        @enabled
      end

      attr_reader :auto_approve_limit, :currency

      # 是否需要第二人批准（策略不适用 → 不需要）。
      def requires_approval?(amount:, currency: nil)
        return false unless enabled?
        return false unless applies_to_currency?(currency)

        BigDecimal(amount.to_s) > auto_approve_limit
      end

      def auto_approves?(amount:, currency: nil)
        enabled? && !requires_approval?(amount: amount, currency: currency)
      end

      # 策略是否覆盖该币种（策略未限定币种 → 覆盖全部）。
      def applies_to_currency?(currency)
        return true if @currency.blank?

        currency.to_s.strip.upcase == @currency
      end

      # 审批行上的快照（「当时按什么规则挂起」）。
      def snapshot
        {
          'enabled' => enabled?,
          'auto_approve_limit' => auto_approve_limit.to_s('F'),
          'currency' => currency,
          'reason' => reason
        }
      end

      def to_h
        snapshot
      end

      private

      def truthy?(value)
        TRUE_VALUES.include?(value) || value.to_s.strip.downcase == 'true'
      end

      def normalize_currency(value)
        text = value.to_s.strip
        text.empty? ? nil : text.upcase
      end

      # @return [Array(BigDecimal, String)] [阈值, reason]
      def resolve_limit
        return [BigDecimal('0'), 'disabled'] unless @enabled
        return [BigDecimal('0'), 'limit_missing_conservative'] if @raw_limit.nil? || @raw_limit.to_s.strip.empty?

        parsed = BigDecimal(@raw_limit.to_s.strip.tr(',', ''))
        return [BigDecimal('0'), 'invalid_limit'] if parsed.negative?

        [parsed, 'ok']
      rescue ArgumentError, TypeError
        [BigDecimal('0'), 'invalid_limit']
      end
    end
  end
end
