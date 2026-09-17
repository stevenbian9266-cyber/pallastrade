# frozen_string_literal: true

# PALLAS-CUSTOM: D3（PRD-20260917-payments-d3-risk-dashboard-threshold-alerts；业务方案 §78-D3 / §72.5）
#
# Risk::DashboardThreshold —— 把「指标值 + 策略」判成**档位**的纯函数（零 I/O、零写库）。
#
# 档位语义（写死，页面/告警共用）：
#   * `ok`           —— 已配置且低于 warning；
#   * `approaching`  —— 达到 warning（含）未达 critical（= 业务方案 §72.5「逼近阈值即预警」）；
#   * `breached`     —— 达到 critical（含）；
#   * `unconfigured` —— 该指标**没配双阈值**：不判定（拿默认值当"运营决策"是错的）；
#   * `unavailable`  —— 值本身不可判定（分母为 0 / 数据源降级）：同样不判定。
#
# 方向：本切片 5 个指标一律「越高越坏」（`higher_is_worse`）；字段保留以便后续扩展。
module PallasTrade
  module Risk
    class DashboardThreshold
      STATUSES = %w[ok approaching breached unconfigured unavailable].freeze
      ALERTING_STATUSES = %w[approaching breached].freeze
      DIRECTION = 'higher_is_worse'

      SEVERITY = { 'unavailable' => 0, 'unconfigured' => 0, 'ok' => 1, 'approaching' => 2, 'breached' => 3 }.freeze

      class << self
        # @param metrics [Array<Hash>] `DashboardReport` 的 metrics
        # @param policy [PallasTrade::Risk::DashboardPolicy]
        # @return [Array<Hash>] 每项 { key:, status:, value:, unit:, threshold:, direction:, reason: }
        def classify(metrics:, policy:)
          Array(metrics).map { |metric| classify_one(metric, policy) }
        end

        def classify_one(metric, policy)
          key = metric[:key].to_s
          threshold = policy.threshold_for(key)
          base = { key: key, unit: metric[:unit], value: metric[:value], threshold: threshold,
                   direction: DIRECTION, window: metric[:window] }

          # 无值 → 不判定（`value: nil` 是「不知道」，不是「健康」）
          return base.merge(status: 'unavailable', reason: metric[:reason] || 'value_unavailable') if metric[:value].nil?

          return base.merge(status: 'unconfigured', reason: 'thresholds_not_configured') unless policy.configured?(key)

          value = metric[:value].to_d
          status = if value >= threshold[:critical].to_d then 'breached'
                   elsif value >= threshold[:warning].to_d then 'approaching'
                   else 'ok'
                   end

          base.merge(status: status, reason: nil)
        end

        # @return [Integer] 严重度（用于「同日不降档」比较）
        def severity(status)
          SEVERITY.fetch(status.to_s, 0)
        end

        def alerting?(status)
          ALERTING_STATUSES.include?(status.to_s)
        end
      end
    end
  end
end
