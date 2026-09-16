# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片2（PRD-20260916-payments-d14b-dispute-deadlines；业务方案 §71.2）——
# `Disputes::DeadlinePolicy` —— 店铺级争议期限策略（**只读**值对象，唯一口径）。
#
# 存储：`Store#private_metadata['dispute_deadline_policy']`（无新表；策略变更写审计）。
# 字段：
#   * `tiers_days`            —— 档位（「截止前 N 天」）数组，默认 `[3, 1]` → 档位键 `t3` / `t1`
#   * `auto_lose_on_overdue`  —— 超期是否**自动置 lost**（默认 **false** = 行为与今天一致）
#   * `auto_lose_limit`       —— 单轮自动置 lost 上限（默认 100，防批量误伤）
#
# 归一化（保守 + 显式）：
#   * `tiers_days` 非法/空 → 回默认 `[3, 1]`（绝不因配置错误而「无档位 = 不提醒」）
#   * 档位去重 + 只保留正整数；返回**降序**（最宽松档在前）
#   * `auto_lose_on_overdue` 非真值 → 关闭；`auto_lose_limit` 非法 → 默认 100
#
# 铁律：读策略**零写库**、零 provider I/O。
module PallasTrade
  module Disputes
    class DeadlinePolicy
      KEY = 'dispute_deadline_policy'
      DEFAULT_TIERS_DAYS = [3, 1].freeze
      DEFAULT_AUTO_LOSE_LIMIT = 100
      OVERDUE = PallasTrade::DisputeDeadlineAlert::OVERDUE_TIER
      TRUE_VALUES = [true, 'true', 1, '1', 'yes', 'on'].freeze

      attr_reader :tiers_days, :auto_lose_limit

      # @param store [PallasTrade::Store, nil]
      # @return [PallasTrade::Disputes::DeadlinePolicy]
      def self.for(store)
        raw = store.respond_to?(:private_metadata) ? (store.private_metadata || {})[KEY] : nil
        new(raw: raw)
      end

      # @param raw [Hash, ActionController::Parameters, nil]
      def initialize(raw: nil)
        config = if raw.is_a?(Hash) then raw
                 elsif raw.respond_to?(:to_unsafe_h) then raw.to_unsafe_h
                 else {}
                 end

        @tiers_days = normalize_tiers(config['tiers_days'] || config[:tiers_days])
        @auto_lose = truthy?(config['auto_lose_on_overdue'] || config[:auto_lose_on_overdue])
        @auto_lose_limit = normalize_limit(config['auto_lose_limit'] || config[:auto_lose_limit])
      end

      def auto_lose_on_overdue?
        @auto_lose
      end

      # 最宽松档位的小时数（扫描窗口；默认 `t3` → 72h，与既有 DSP-P7-5 窗口一致）
      def max_window_hours
        tiers_days.max * 24
      end

      # 档位键列表（宽松 → 紧迫），如 `['t3', 't1']`
      def tiers
        @tiers ||= tiers_days.map { |days| "t#{days}" }
      end

      # 已到达的档位（升序紧迫度：`['t3', 't1', 'overdue']`），用于**补齐台账不遗漏**
      # @param hours_remaining [Numeric]
      # @return [Array<String>]
      def reached_tiers(hours_remaining:)
        remaining = hours_remaining.to_f
        reached = tiers.select { |tier| remaining <= tier_hours(tier) }
        reached << OVERDUE if remaining.negative?
        reached
      end

      # 当前生效的最高（最紧迫）档位；未进入任何档位 → nil
      # @param hours_remaining [Numeric]
      # @return [String, nil]
      def latest_tier(hours_remaining:)
        reached_tiers(hours_remaining: hours_remaining).last
      end

      def tier_hours(tier)
        days = tier.to_s[/\At(\d+)\z/, 1]
        (days ? days.to_i : 0) * 24
      end

      # 策略快照（写台账/审计时留痕「按什么规则提醒」）
      def snapshot
        {
          'tiers_days' => tiers_days,
          'auto_lose_on_overdue' => auto_lose_on_overdue?,
          'auto_lose_limit' => auto_lose_limit
        }
      end

      def to_h
        snapshot
      end

      private

      def truthy?(value)
        TRUE_VALUES.include?(value) || value.to_s.strip.downcase == 'true'
      end

      # @return [Array<Integer>] 降序正整数（非法 → 默认）
      def normalize_tiers(value)
        raw = value.is_a?(Array) ? value : value.to_s.split(',')
        days = raw.map { |item| item.to_s.strip }.reject(&:empty?).map do |item|
          Integer(item, exception: false)
        end
        days = days.compact.select(&:positive?).uniq.sort.reverse
        days.presence || DEFAULT_TIERS_DAYS
      end

      def normalize_limit(value)
        parsed = Integer(value.to_s.strip, exception: false)
        return DEFAULT_AUTO_LOSE_LIMIT if parsed.nil? || parsed <= 0

        parsed
      end
    end
  end
end
