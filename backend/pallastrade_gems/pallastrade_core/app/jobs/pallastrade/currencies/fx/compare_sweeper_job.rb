# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# `Currencies::Fx::CompareSweeperJob` —— 结算汇率对比巡检（sidekiq-cron）。
#
# 边界（结算差核算，不做资金决策）：
#   * **只**比对锁汇快照与结算台账，写快照对比结果 + 差异案例 + 审计 + 结构化日志；
#   * **绝不**改订单/支付金额与状态、不退款、不写账本/库存、不调 provider（零外呼）。
#
# 幂等/可重跑：同输入同结果；重复调度不产生第二行案例（dedupe 键稳定）。
# 调度：`backend/config/sidekiq_schedule.rb` 的 `fx_rate_compare_sweep`（每 30 分钟）。
module PallasTrade
  module Currencies
    module Fx
      class CompareSweeperJob < PallasTrade::BaseJob
        queue_as PallasTrade.queues.default

        # @param store_code [String, nil] 只扫指定店铺（默认全店）
        # @param lookback_days [Integer] 扫描期间（默认 90 天）
        # @return [Hash] 运行摘要（累加 + 失败隔离）
        def perform(store_code: nil, lookback_days: 90)
          stores = scope_stores(store_code)
          summary = { stores: stores.size, scanned: 0, compared: 0, matched: 0, mismatched: 0, pending: 0,
                      undetermined: 0, opened: 0, touched: 0, closed: 0, failed: 0 }

          stores.each do |store|
            merge_run(store, lookback_days, summary)
          rescue StandardError => e
            summary[:failed] += 1
            Rails.logger.error(
              "[Currencies::Fx::CompareSweeperJob] store #{store.id} failed: #{e.class} #{e.message}"
            )
          end

          Rails.logger.info(JSON.generate({ event: 'fx.rate_compare_sweeper' }.merge(summary)))
          summary
        end

        private

        def scope_stores(store_code)
          scope = PallasTrade::Store.all
          scope = scope.where(code: store_code) if store_code.present?
          scope.order(:id).to_a
        end

        def merge_run(store, lookback_days, summary)
          from = lookback_days.to_i.days.ago
          result = PallasTrade::Currencies::Fx::Compare.call(store: store, from: from, to: Time.current, detail: false)
          raise "compare failed: #{result.error}" unless result.success?

          value = result.value
          %i[scanned compared matched mismatched pending undetermined].each do |key|
            summary[key] += value[key].to_i
          end
          %i[opened touched closed].each do |key|
            summary[key] += Array(value.dig(:cases, key)).size
          end
        end
      end
    end
  end
end
