# frozen_string_literal: true

# PALLAS-CUSTOM: D3（PRD-20260917-payments-d3-risk-dashboard-threshold-alerts；业务方案 §78-D3 / §60.2-P3 / §72.5）
#
# Risk::DashboardPolicy —— 支付风控看板的**唯一读写口径**。
# 栖于 `store.private_metadata['payment_risk_dashboard_policy']`（与 `dispute_rate_policy` /
# `three_d_secure_policy` 同先例；**零迁移**）。
#
# 两条路径语义不同（沿用 D15c 先例）：
#   * `normalize`（读）**永不抛错** —— 运营写坏一个键不能让后台 500：非法值回落默认并记 `reasons`；
#   * `storable`（写）**拒绝式** —— 非法值返回字段级 `errors` 且**不落库**。
#
# 单位约定：比率类指标一律 **bps（万分比）**（与 D14c 同单位，便于阈值配置与跨指标对比）；
# 队列时长用**分钟**。展示层再转百分比 / 小时。
module PallasTrade
  module Risk
    class DashboardPolicy
      KEY = 'payment_risk_dashboard_policy'

      # 指标键（顺序即页面展示顺序；不可增删——服务/页面/spec 三处同源）
      METRICS = %w[
        risky_orders
        three_ds_challenge_rate
        dispute_rate
        refund_rate
        review_queue_duration
      ].freeze

      RATIO_METRICS = %w[risky_orders three_ds_challenge_rate dispute_rate refund_rate].freeze
      DURATION_METRICS = %w[review_queue_duration].freeze

      MIN_WINDOW_DAYS = 1
      MAX_WINDOW_DAYS = 365
      MAX_BPS = 10_000
      MAX_DURATION_MINUTES = 10_080 # 7 天
      FALSE_VALUES = [false, 'false', 0, '0', 'off', 'no'].freeze

      # 默认阈值：**保守的起始参考值**（非监管公告值）；运营应按自身水位复核后调整。
      # dispute_rate 与 D14c 的建议模板同量级（65/100 bps），避免两个页面口径漂移。
      DEFAULT_THRESHOLDS = {
        'risky_orders' => { 'warning' => 300, 'critical' => 600 },
        'three_ds_challenge_rate' => { 'warning' => 3_000, 'critical' => 5_000 },
        'dispute_rate' => { 'warning' => 65, 'critical' => 100 },
        'refund_rate' => { 'warning' => 1_000, 'critical' => 2_000 },
        'review_queue_duration' => { 'warning' => 120, 'critical' => 240 }
      }.freeze

      DEFAULT_ENABLED = %w[dispute_rate review_queue_duration].freeze

      attr_reader :window_days, :metrics, :reasons

      class << self
        # @param store [PallasTrade::Store, nil]
        # @return [PallasTrade::Risk::DashboardPolicy]
        def for(store)
          raw = store.respond_to?(:private_metadata) ? (store.private_metadata || {})[KEY] : nil
          new(raw: raw)
        end

        # @return [Array<String>] 指标键（页面/服务共用，禁止各处硬编码）
        def metric_keys
          METRICS
        end

        def default_thresholds
          DEFAULT_THRESHOLDS.each_with_object({}) do |(key, values), acc|
            acc[key] = values.transform_values(&:to_i)
          end
        end

        # 写路径校验：非法值 → errors（不落库）。返回 [policy, errors]。
        # @param raw [Hash, ActionController::Parameters, nil]
        # @return [Array(PallasTrade::Risk::DashboardPolicy, Array<Hash>)]
        def storable(raw: nil)
          config = stringify(raw)
          errors = []

          window = config['window_days']
          if window.present? && !valid_integer?(window, MIN_WINDOW_DAYS, MAX_WINDOW_DAYS)
            errors << { field: 'window_days', code: 'out_of_range',
                        message: "window_days must be an integer between #{MIN_WINDOW_DAYS} and #{MAX_WINDOW_DAYS}" }
          end

          given = config['metrics']
          unless given.nil? || given.is_a?(Hash)
            errors << { field: 'metrics', code: 'invalid_type', message: 'metrics must be a mapping of metric key to thresholds' }
            given = nil
          end

          (given || {}).each do |metric, thresholds|
            metric = metric.to_s
            unless METRICS.include?(metric)
              errors << { field: "metrics.#{metric}", code: 'unknown_metric',
                          message: "unknown metric key '#{metric}'" }
              next
            end

            errors.concat(threshold_errors(metric, thresholds))
          end

          [new(raw: config), errors]
        end

        def stringify(raw)
          return {} if raw.nil?

          source = if raw.is_a?(Hash) then raw
                   elsif raw.respond_to?(:to_unsafe_h) then raw.to_unsafe_h
                   else {}
                   end
          source.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
        end

        private

        def threshold_errors(metric, thresholds)
          errors = []
          unless thresholds.is_a?(Hash)
            return [{ field: "metrics.#{metric}", code: 'invalid_type',
                      message: 'thresholds must be a mapping of warning/critical' }]
          end

          values = thresholds.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
          ceiling = DURATION_METRICS.include?(metric) ? MAX_DURATION_MINUTES : MAX_BPS

          %w[warning critical].each do |level|
            value = values[level]
            next if value.nil?

            unless valid_integer?(value, 1, ceiling)
              errors << { field: "metrics.#{metric}.#{level}", code: 'out_of_range',
                          message: "#{level} must be an integer between 1 and #{ceiling}" }
            end
          end

          warning = integer_or_nil(values['warning'])
          critical = integer_or_nil(values['critical'])
          if warning && critical && warning >= critical
            errors << { field: "metrics.#{metric}", code: 'warning_not_below_critical',
                        message: 'warning threshold must be lower than critical threshold' }
          end
          errors
        end

        def integer_or_nil(value)
          return nil if value.nil? || value == ''

          Integer(value.to_s, exception: false)
        end

        def valid_integer?(value, min, max)
          parsed = integer_or_nil(value)
          parsed.present? && parsed >= min && parsed <= max
        end
      end

      # @param raw [Hash, ActionController::Parameters, nil]
      def initialize(raw: nil)
        config = self.class.stringify(raw)

        @reasons = []
        @window_days = normalize_window(config['window_days'])
        @metrics = normalize_metrics(config['metrics'])
      end

      def enabled?(metric)
        metric = metric.to_s
        @metrics.fetch(metric, {})[:enabled] == true
      end

      # @return [Hash] { warning:, critical: }（整数；缺失用默认值补齐）
      def threshold_for(metric)
        metric = metric.to_s
        @metrics.fetch(metric, {})[:thresholds] || default_threshold(metric)
      end

      # 已配置 = 该指标启用**且**双阈值都显式存在（否则不判定，避免拿默认值当"运营决策"）
      def configured?(metric)
        metric = metric.to_s
        return false unless enabled?(metric)

        entry = @metrics[metric]
        entry.present? && entry[:explicit_warning] && entry[:explicit_critical]
      end

      def to_h
        {
          window_days: @window_days,
          metrics: METRICS.index_with { |metric| metric_config(metric) },
          reasons: @reasons
        }
      end

      def metric_config(metric)
        entry = @metrics.fetch(metric.to_s, {})
        {
          enabled: entry[:enabled] == true,
          configured: configured?(metric),
          warning: threshold_for(metric)[:warning],
          critical: threshold_for(metric)[:critical]
        }
      end

      def raw
        {
          'window_days' => @window_days,
          'metrics' => METRICS.index_with do |metric|
            thresholds = threshold_for(metric)
            { 'enabled' => enabled?(metric), 'warning' => thresholds[:warning], 'critical' => thresholds[:critical] }
          end
        }
      end

      private

      def normalize_window(value)
        parsed = self.class.send(:integer_or_nil, value)
        return 30 if parsed.nil?

        if parsed < MIN_WINDOW_DAYS || parsed > MAX_WINDOW_DAYS
          @reasons << 'window_days_out_of_range'
          return 30
        end

        parsed
      end

      def normalize_metrics(raw)
        given = raw.is_a?(Hash) ? raw : {}
        METRICS.each_with_object({}) do |metric, acc|
          source = given[metric] || given[metric.to_s] || {}
          source = {} unless source.is_a?(Hash)
          normalized = source.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }

          enabled = normalized.key?('enabled') ? !FALSE_VALUES.include?(normalized['enabled']) : DEFAULT_ENABLED.include?(metric)
          warning = self.class.send(:integer_or_nil, normalized['warning'])
          critical = self.class.send(:integer_or_nil, normalized['critical'])

          acc[metric] = {
            enabled: enabled,
            explicit_warning: warning.present?,
            explicit_critical: critical.present?,
            thresholds: normalized_thresholds(metric, warning, critical)
          }
        end
      end

      # 读路径 fail-safe：非法/缺失 → 回落默认（并记 reasons），保证页面恒可渲染
      def normalized_thresholds(metric, warning, critical)
        ceiling = DURATION_METRICS.include?(metric) ? MAX_DURATION_MINUTES : MAX_BPS
        fallback = default_threshold(metric)
        warning = fallback[:warning] unless warning && warning.positive? && warning <= ceiling
        critical = fallback[:critical] unless critical && critical.positive? && critical <= ceiling

        if warning >= critical
          @reasons << "#{metric}_thresholds_out_of_order"
          return fallback
        end

        { warning: warning, critical: critical }
      end

      def default_threshold(metric)
        values = DEFAULT_THRESHOLDS[metric.to_s] || { 'warning' => 1, 'critical' => 2 }
        { warning: values['warning'], critical: values['critical'] }
      end
    end
  end
end
