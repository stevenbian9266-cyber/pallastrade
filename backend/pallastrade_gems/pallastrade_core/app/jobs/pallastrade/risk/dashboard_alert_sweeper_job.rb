# frozen_string_literal: true

# PALLAS-CUSTOM: D3（PRD-20260917-payments-d3-risk-dashboard-threshold-alerts；业务方案 §78-D3）
#
# Risk::DashboardAlertSweeperJob —— 支付风控水位巡检（sidekiq-cron 每小时）。
#
# 边界：
#   * **只**调 `Risk::DashboardAlert`（审计留痕 + 事件），**零**资金/订单/provider 副作用；
#   * **逐店隔离**：单店异常只记日志并计入 `failed`，不影响其它店；
#   * **可重跑**：幂等由 `DashboardAlert` 保证（同店同指标同档位同日一次；同日不降档）。
#
# 调度：`backend/config/sidekiq_schedule.rb` 的 `risk_dashboard_alert_sweep`（每小时 :05）。
module PallasTrade
  module Risk
    class DashboardAlertSweeperJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      # @param store_id [Integer, String, nil] 只跑单店（排障用）；缺省跑全部店铺
      # @param window_days [Integer, nil] 覆盖店铺策略窗口
      # @return [Hash] 运行摘要
      def perform(store_id: nil, window_days: nil)
        summary = { evaluated: 0, alerts: 0, recorded: 0, events: 0, skipped: 0, failed: 0,
                    scanned_at: Time.current.iso8601 }

        stores_for(store_id).each do |store|
          outcome = PallasTrade::Risk::DashboardAlert.call(store: store, window_days: window_days)
          unless outcome.success?
            summary[:failed] += 1
            Rails.logger.error(
              "[Risk::DashboardAlertSweeperJob] store #{store.id} failed: #{outcome.error}"
            )
            next
          end

          value = outcome.value
          summary[:evaluated] += 1
          summary[:alerts] += Array(value[:alerts]).size
          summary[:recorded] += Array(value[:recorded]).size
          summary[:events] += Array(value[:events]).size
          summary[:skipped] += Array(value[:skipped]).size
        rescue StandardError => e
          summary[:failed] += 1
          Rails.logger.error(
            "[Risk::DashboardAlertSweeperJob] store #{store.id} raised: #{e.class} #{e.message}"
          )
        end

        Rails.logger.info(JSON.generate({ event: 'risk.dashboard_alert_sweeper' }.merge(summary)))
        summary
      end

      private

      def stores_for(store_id)
        return [PallasTrade::Store.find_by(id: store_id)].compact if store_id.present?

        PallasTrade::Store.order(:id).to_a
      end
    end
  end
end
