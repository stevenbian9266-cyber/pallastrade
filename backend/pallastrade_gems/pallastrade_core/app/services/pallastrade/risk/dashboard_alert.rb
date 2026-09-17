# frozen_string_literal: true

# PALLAS-CUSTOM: D3（PRD-20260917-payments-d3-risk-dashboard-threshold-alerts；业务方案 §78-D3 / §72.5）
#
# Risk::DashboardAlert —— 把「指标档位」落成**可追溯告警**（审计行即留痕）+ 按需发布事件。
#
# 职责边界（与 D14c `Disputes::RateAlert` 的差异写在这里）：
#   * **不新建台账表**：本切片是**店铺级单值水位**，用审计行（唯一幂等键 + 前后值 + 指标/值/阈值）
#     即可满足「可查、可追溯、幂等」；D14c 建表是因为它需要「按卡组织 × 评估日」的多行状态机；
#   * **只对已配置阈值且达到档位**的指标写审计（`ok` / `unconfigured` / `unavailable` 不写，避免噪声）；
#   * **幂等**：同店 + 同指标 + 同档位 + 同评估日只写一次；**同日不降档**（今天已记 `breached`，
#     之后降到 `approaching` 不再写、不再发）；
#   * **零资金副作用**：不改支付/订单/交易/退款状态，零 provider 调用；
#   * 事件载荷**无 PII**：只含 store_id / metric / status / value / unit / threshold / window / evaluated_at。
#
# 事件：`payments.risk_dashboard_threshold`（仅档位新进入或升级时发布；事件系统未启用或发布失败只记日志）。
module PallasTrade
  module Risk
    class DashboardAlert
      prepend PallasTrade::ServiceModule::Base

      EVENT_NAME = 'payments.risk_dashboard_threshold'
      AUDIT_ACTION = 'payment_risk_dashboard_threshold'
      RESOURCE_TYPE = 'PallasTrade::Store'

      # @param store [PallasTrade::Store]
      # @param now [Time]
      # @param window_days [Integer, nil] 覆盖策略窗口
      # @param report [Hash, nil] 复用已算好的 `DashboardReport` 结果（避免重复计算）
      # @return [PallasTrade::ServiceModule::Result] success({ store_id:, evaluated_at:, alerts:, recorded:, events:, skipped: })
      def call(store:, now: Time.current, window_days: nil, report: nil)
        return failure(nil, 'Store is required') if store.nil?

        @store = store
        @now = now
        @policy = PallasTrade::Risk::DashboardPolicy.for(store)

        outcome = report.present? ? success(report) : PallasTrade::Risk::DashboardReport.call(store: store, window_days: window_days, now: now)
        unless outcome.success?
          return failure(store, { code: 'dashboard_report_failed', message: outcome.error.to_s })
        end

        data = outcome.value
        if data[:degraded].present?
          return success(base_summary.merge(alerts: [], recorded: [], events: [],
                                            skipped: data[:degraded].map { |reason| "report_degraded:#{reason}" }))
        end

        rows = PallasTrade::Risk::DashboardThreshold.classify(metrics: data[:metrics], policy: @policy)
        alerts = rows.select { |row| PallasTrade::Risk::DashboardThreshold.alerting?(row[:status]) }

        recorded = []
        events = []
        skipped = []

        alerts.each do |row|
          reason = skip_reason(row)
          if reason.present?
            skipped << reason
            next
          end

          record_audit(row)
          recorded << { metric: row[:key], status: row[:status], value: row[:value], threshold: row[:threshold] }
          events << publish_event(row, data)
        end

        success(base_summary.merge(evaluated_at: data[:evaluated_at],
                                   alerts: alerts.map { |row| row.slice(:key, :status, :value, :unit, :threshold) },
                                   recorded: recorded, events: events.compact, skipped: skipped.uniq))
      end

      private

      def base_summary
        { store_id: @store.id, evaluated_at: @now, alerts: [], recorded: [], events: [], skipped: [] }
      end

      # 幂等 + 同日不降档（当日审计行即幂等键；不建表）
      def skip_reason(row)
        key = row[:key].to_s
        recorded_today = today_records[key]
        return nil if recorded_today.blank?

        status = row[:status].to_s
        return "duplicate:#{key}:#{status}" if recorded_today.include?(status)

        max_severity = recorded_today.map { |s| PallasTrade::Risk::DashboardThreshold.severity(s) }.max
        if max_severity > PallasTrade::Risk::DashboardThreshold.severity(status)
          return "no_downgrade_same_day:#{key}:#{status}"
        end

        nil
      end

      # 当日该店已记录的 { metric => [statuses] }（一次查询，内存判重）
      def today_records
        @today_records ||= begin
          rows = PallasTrade::AuditLog
                 .where(action: AUDIT_ACTION, resource_type: RESOURCE_TYPE, resource_id: @store.id)
                 .where(created_at: @now.beginning_of_day..@now)
          rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |row, acc|
            metadata = row.metadata.to_h
            metric = metadata['metric'].to_s
            status = metadata['status'].to_s
            acc[metric] << status if metric.present? && status.present?
          end
        end
      end

      def record_audit(row)
        PallasTrade::Audit.record(
          action: AUDIT_ACTION,
          actor: 'system',
          resource: @store,
          before: { status: 'ok' },
          after: { status: row[:status], value: row[:value] },
          metadata: {
            'metric' => row[:key].to_s,
            'status' => row[:status].to_s,
            'value' => row[:value],
            'unit' => row[:unit],
            'warning' => row[:threshold][:warning],
            'critical' => row[:threshold][:critical],
            'direction' => row[:direction],
            'evaluated_at' => @now.iso8601
          }
        )
      end

      def publish_event(row, data)
        return nil unless PallasTrade::Events.respond_to?(:enabled?) && PallasTrade::Events.enabled?

        payload = {
          store_id: @store.id,
          metric: row[:key].to_s,
          status: row[:status].to_s,
          value: row[:value],
          unit: row[:unit],
          warning: row[:threshold][:warning],
          critical: row[:threshold][:critical],
          window_days: data.dig(:scope, :window_days),
          evaluated_at: (data[:evaluated_at] || @now).iso8601
        }
        PallasTrade::Events.publish(EVENT_NAME, payload)
        payload
      rescue StandardError => e
        Rails.logger.error("[Risk::DashboardAlert] publish failed: #{e.class} #{e.message}")
        nil
      end
    end
  end
end
