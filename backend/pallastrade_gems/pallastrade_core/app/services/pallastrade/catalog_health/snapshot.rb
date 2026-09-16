# frozen_string_literal: true

module PallasTrade
  module CatalogHealth
    # 采集某店某日的 7 类 issue 计数（PRD-20260916-catalog-health-trend-snapshot FR-002）。
    #
    # 铁律：计数**只能**来自 `Issues.count` —— 那是唯一口径权威（工作台的计数与下钻列表都由它派生，
    # 「计数 == 列表条数」这条不变量靠它维持）。在这里另写一套判定 SQL 会让快照与工作台悄悄漂移，
    # 而趋势恰恰是用来判断"治理有没有效果"的，漂移即失真。
    #
    # 幂等：同店/同日/同 key 只有一行，重跑覆盖当次值（唯一索引兜底；并发撞索引时重试一次）。
    module Snapshot
      class << self
        # @param store [PallasTrade::Store]
        # @param on [Date] 快照归属日（可回填历史日，便于补跑）
        # @return [Array<PallasTrade::CatalogHealthSnapshot>] 写入的行
        def capture(store, on: Date.current)
          Issues::KEYS.map { |key| capture_one(store, key, on) }
        end

        private

        def capture_one(store, key, on)
          write(store, key, on, retries: 1)
        end

        def write(store, key, on, retries:)
          record = PallasTrade::CatalogHealthSnapshot.find_or_initialize_by(
            store_id: store.id, issue_key: key, captured_on: on
          )
          record.count = Issues.count(store, key)
          record.save!
          record
        rescue ActiveRecord::RecordNotUnique
          # 并发写入同一天同一 issue：唯一索引已经保证只有一行，重试即落到更新分支。
          raise if retries.zero?

          write(store, key, on, retries: retries - 1)
        end
      end
    end
  end
end
