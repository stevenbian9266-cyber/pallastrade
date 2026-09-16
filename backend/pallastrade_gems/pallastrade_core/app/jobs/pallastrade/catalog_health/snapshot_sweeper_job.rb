# frozen_string_literal: true

# G-7（PRD-20260916-catalog-health-trend-snapshot FR-003）
#
# CatalogHealth::SnapshotSweeperJob —— 每日采集所有店铺的 Catalog Health 快照（sidekiq-cron）。
#
# 边界：
#   - **只写快照表**（NFR-002）：不触碰商品/媒体/翻译/redirect，不发事件，不修数据；
#   - **单店失败不阻断**：某个店的判定 SQL 出错不应该让其余店当天没有数据（趋势断档比噪声更糟）；
#   - **有界**：店铺数上限，避免异常环境拖垮作业。
#
# 幂等/可重跑：同日重跑覆盖当次计数（唯一索引 `(store_id, issue_key, captured_on)` 兜底），
# 因此**补跑历史日**是安全的（`on:` 可回填）。
#
# 调度：`backend/config/sidekiq_schedule.rb` 的 `catalog_health_snapshot`（每日 02:00，
# 错开 01:00 争议期限扫描 / 01:30 争议收敛 sweeper）。
module PallasTrade
  module CatalogHealth
    class SnapshotSweeperJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      STORE_LIMIT = 500

      # @param store_limit [Integer] 最多采集多少家店（有界）
      # @param on [String, nil] 快照归属日（ISO，默认今天；用于补跑）
      # @return [Hash] 运行摘要 { stores_captured:, stores_failed:, captured_on:, rows_written: }
      def perform(store_limit: STORE_LIMIT, on: nil)
        date = parse_on(on)
        captured = 0
        rows_written = 0
        failed = []

        PallasTrade::Store.limit(store_limit.to_i.positive? ? store_limit.to_i : STORE_LIMIT).find_each do |store|
          begin
            rows_written += PallasTrade::CatalogHealth::Snapshot.capture(store, on: date).size
            captured += 1
          rescue StandardError => e
            failed << { store_id: store.id, error: e.class.name, message: e.message.to_s.truncate(200) }
            Rails.logger.error(
              "[CatalogHealth::SnapshotSweeperJob] capture failed for store #{store.id}: #{e.class} #{e.message}"
            )
          end
        end

        { stores_captured: captured, stores_failed: failed, captured_on: date.to_s, rows_written: rows_written }
      end

      private

      def parse_on(value)
        return Date.current if value.blank?

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        Date.current
      end
    end
  end
end
