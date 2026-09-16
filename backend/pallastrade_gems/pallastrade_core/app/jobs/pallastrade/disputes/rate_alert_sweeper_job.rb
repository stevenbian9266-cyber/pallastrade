# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片3（PRD-20260916-payments-d14c-dispute-rate-board；业务方案 §71.3 + §72.5）——
# `Disputes::RateAlertSweeperJob` —— **拒付率阈值巡检**：逐店铺评估 → 落预警台账 → 按需发事件。
#
# 铁律：
#   * **只读 + 只写台账**：不碰支付/订单/退款/账本/库存/争议状态，零 provider 调用（纯本地统计）；
#   * **单店失败隔离**：某店异常只记 `failed`，其余店铺继续；
#   * 结构化指标日志 `{"event":"dispute.rate_alert_sweeper", ...}`，供运维抓取。
module PallasTrade
  module Disputes
    class RateAlertSweeperJob
      EVENT_NAME = 'dispute.rate_alert_sweeper'

      # @param window_days [Integer, nil] 覆盖策略窗口（默认取店铺策略）
      # @return [Hash] 指标计数
      def perform(window_days: nil)
        metrics = { stores: 0, evaluated: 0, recorded: 0, escalated: 0, skipped: 0, failed: 0 }

        PallasTrade::Store.find_each do |store|
          metrics[:stores] += 1
          begin
            result = PallasTrade::Disputes::RateAlert.call(store: store, window_days: window_days)
            if result.success?
              metrics[:evaluated] += 1
              metrics[:recorded] += Array(result.value[:recorded]).size
              metrics[:escalated] += Array(result.value[:escalated]).size
              metrics[:skipped] += Array(result.value[:skipped]).size
            else
              metrics[:failed] += 1
              Rails.logger.error(
                "[Disputes::RateAlertSweeperJob] store #{store.id} failed: #{result.error&.to_s}"
              )
            end
          rescue StandardError => e
            metrics[:failed] += 1
            Rails.logger.error(
              "[Disputes::RateAlertSweeperJob] store #{store.id} raised: #{e.class} #{e.message}"
            )
          end
        end

        Rails.logger.info({ event: EVENT_NAME }.merge(metrics).to_json)
        metrics
      end
    end
  end
end
