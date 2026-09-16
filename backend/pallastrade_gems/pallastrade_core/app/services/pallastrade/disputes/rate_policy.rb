# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片3（PRD-20260916-payments-d14c-dispute-rate-board；业务方案 §71.3 + §72.5）——
# `Disputes::RatePolicy` —— 店铺级**拒付率阈值策略**（**只读**值对象，唯一口径）。
#
# 存储：`Store#private_metadata['dispute_rate_policy']`（无新表；策略变更由后台写审计）。
# 字段：
#   * `enabled`        —— 是否启用预警（默认 **true**；关闭后看板仍展示比率，但不落台账、不发事件）
#   * `window_days`    —— 比率窗口天数（默认 **30**，允许 1–365）
#   * `warning_ratio`  —— 预警比例（默认 **0.8** = 业务方案 §72.5「接近卡组织阈值 80% 时预警」）
#   * `networks`       —— `{ '<卡组织键>' => { 'count_bps' => N, 'amount_bps' => M } }`（bps = 万分之一）
#
# **不硬编码卡组织公示数字**：默认 `networks` 为空 → 未配置的组织一律 `unconfigured`（不判定、不预警）。
# `SUGGESTED` 只是「建议模板」（带来源说明），必须由运营**显式应用**才会写进策略。
#
# 归一化（保守 + 显式）：
#   * 窗口非法 → 默认 30；超上限 → 截到 365（不因配置错误而「无窗口」）
#   * 预警比例非法/越界 → 默认 0.8
#   * 阈值非法（非正整数 / > 10000 bps）→ 该指标视为**未配置**（不猜阈值）
#   * `networks` 非 Hash → 空；组织键归一（去空白 + 小写）
#
# 铁律：读策略**零写库**、零 provider I/O。
module PallasTrade
  module Disputes
    class RatePolicy
      KEY = 'dispute_rate_policy'

      DEFAULT_WINDOW_DAYS = 30
      MIN_WINDOW_DAYS = 1
      MAX_WINDOW_DAYS = 365
      DEFAULT_WARNING_RATIO = 0.8
      MIN_WARNING_RATIO = 0.5
      MAX_WARNING_RATIO = 1.0
      MAX_THRESHOLD_BPS = 10_000
      METRICS = %w[count amount].freeze
      FALSE_VALUES = [false, 'false', 0, '0', 'off', 'no'].freeze

      # 建议模板：**不自动生效**；数字需按卡组织最新公告复核后由运营显式应用。
      SUGGESTED = {
        'visa' => { 'count_bps' => 65, 'amount_bps' => 90 },
        'master' => { 'count_bps' => 100, 'amount_bps' => 100 }
      }.freeze
      SUGGESTED_SOURCE_NOTE = 'Visa VAMP / Mastercard ECP 类监管项目的公示阈值会随公告调整，' \
                              '本模板仅为起始参考值，落地前必须按卡组织最新规则复核'

      attr_reader :window_days, :warning_ratio, :networks

      class << self
        # @param store [PallasTrade::Store, nil]
        # @return [PallasTrade::Disputes::RatePolicy]
        def for(store)
          raw = store.respond_to?(:private_metadata) ? (store.private_metadata || {})[KEY] : nil
          new(raw: raw)
        end

        # 建议模板的深拷贝（后台「应用建议值」用；调用方不得直接改常量）
        # @return [Hash]
        def suggested_networks
          SUGGESTED.each_with_object({}) do |(network, values), acc|
            acc[network] = values.transform_values(&:to_i)
          end
        end

        def suggested_source_note
          SUGGESTED_SOURCE_NOTE
        end
      end

      # @param raw [Hash, ActionController::Parameters, nil]
      def initialize(raw: nil)
        config = if raw.is_a?(Hash) then raw
                 elsif raw.respond_to?(:to_unsafe_h) then raw.to_unsafe_h
                 else {}
                 end
        config = config.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }

        @enabled = !FALSE_VALUES.include?(config['enabled'])
        @window_days = normalize_window(config['window_days'])
        @warning_ratio = normalize_warning_ratio(config['warning_ratio'])
        @networks = normalize_networks(config['networks'])
      end

      def enabled?
        @enabled
      end

      # 已配置双阈值的组织键（升序，页面/服务共用）
      # @return [Array<String>]
      def configured_networks
        networks.select { |_network, thresholds| thresholds.values.any? }.keys.sort
      end

      # @param network [String, nil]
      # @return [Hash, nil] `{ count_bps:, amount_bps: }`（可能某项为 nil）；未配置 → nil
      def thresholds_for(network)
        thresholds = networks[normalize_network(network)]
        return nil if thresholds.nil? || thresholds.values.compact.empty?

        thresholds
      end

      def configured?(network)
        thresholds_for(network).present?
      end

      # 状态判定（**唯一口径**：报表与预警服务共用，避免「同一指标两种算法」）
      # @param network [String]
      # @param count_ratio [BigDecimal, Float, nil] 笔数比（0.0065 = 0.65%）
      # @param amount_ratio [BigDecimal, Float, nil]
      # @return [Hash] `{ network:, status:, triggered_metrics: [], count_bps:, amount_bps: }`
      def classify(network:, count_ratio: nil, amount_ratio: nil)
        thresholds = thresholds_for(network)
        observed = { 'count' => ratio_to_bps(count_ratio), 'amount' => ratio_to_bps(amount_ratio) }
        return unclassified(network, observed) if thresholds.nil?

        triggered = []
        breached = false
        approaching = false

        METRICS.each do |metric|
          bps = observed[metric]
          limit = thresholds[:"#{metric}_bps"] || thresholds[metric.to_sym]
          next if bps.nil? || limit.nil?

          if bps >= limit
            breached = true
            triggered << metric
          elsif bps >= warning_bps(limit)
            approaching = true
            triggered << metric
          end
        end

        {
          network: normalize_network(network),
          status: breached ? DisputeRateAlert::BREACHED : (approaching ? DisputeRateAlert::APPROACHING : 'ok'),
          triggered_metrics: triggered,
          count_bps: observed['count'],
          amount_bps: observed['amount'],
          count_threshold_bps: thresholds[:count_bps] || thresholds['count_bps'],
          amount_threshold_bps: thresholds[:amount_bps] || thresholds['amount_bps']
        }
      end

      # 阈值 × 预警比例（bps，向下取整；如 65 bps × 0.8 = 52 bps）
      # @return [Integer]
      def warning_bps(threshold_bps)
        (threshold_bps.to_d * warning_ratio.to_d).floor
      end

      # 比率 → bps（万分之一）；nil 透传
      # @return [Integer, nil]
      def ratio_to_bps(ratio)
        return nil if ratio.nil?

        (ratio.to_d * 10_000).round
      end

      private

      def unclassified(network, observed)
        {
          network: normalize_network(network),
          status: 'unconfigured',
          triggered_metrics: [],
          count_bps: observed['count'],
          amount_bps: observed['amount'],
          count_threshold_bps: nil,
          amount_threshold_bps: nil
        }
      end

      def normalize_network(network)
        value = network.to_s.strip.downcase
        value.presence || DisputeRateAlert::UNKNOWN_NETWORK
      end

      def normalize_window(value)
        days = begin
          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end
        return DEFAULT_WINDOW_DAYS if days.nil? || days < MIN_WINDOW_DAYS

        [days, MAX_WINDOW_DAYS].min
      end

      def normalize_warning_ratio(value)
        ratio = begin
          Float(value)
        rescue ArgumentError, TypeError
          nil
        end
        return DEFAULT_WARNING_RATIO if ratio.nil?
        return DEFAULT_WARNING_RATIO if ratio < MIN_WARNING_RATIO || ratio > MAX_WARNING_RATIO

        ratio.round(4)
      end

      # @return [Hash] `{ 'visa' => { count_bps: Integer|nil, amount_bps: Integer|nil } }`
      def normalize_networks(raw)
        return {} unless raw.is_a?(Hash)

        raw.each_with_object({}) do |(network, values), acc|
          key = normalize_network(network)
          next if key.blank? || !values.is_a?(Hash)

          normalized_values = values.each_with_object({}) { |(k, v), inner| inner[k.to_s] = v }
          count_bps = normalize_bps(normalized_values['count_bps'])
          amount_bps = normalize_bps(normalized_values['amount_bps'])
          next if count_bps.nil? && amount_bps.nil?

          acc[key] = { count_bps: count_bps, amount_bps: amount_bps }
        end
      end

      def normalize_bps(value)
        bps = begin
          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end
        return nil if bps.nil? || bps <= 0 || bps > MAX_THRESHOLD_BPS

        bps
      end
    end
  end
end
