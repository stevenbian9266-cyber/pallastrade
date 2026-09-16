# frozen_string_literal: true

module PallasTrade
  # G-7（PRD-20260916-catalog-health-trend-snapshot）：Catalog Health 的**每日一条**计数快照。
  #
  # 快照不是判定 —— 判定口径的唯一权威是 `PallasTrade::CatalogHealth::Issues`（它保证工作台上
  # 「计数 == 下钻列表条数」）。这里只把某一天的口径结果**如实记下来**，所以：
  #   * `issue_key` 必须属于 `Issues::KEYS`：写入未知 key 会在趋势里造出幽灵行；
  #   * `count` 不得为负。
  class CatalogHealthSnapshot < PallasTrade.base_class
    self.table_name = 'pallastrade_catalog_health_snapshots'

    validates :store_id, presence: true
    validates :captured_on, presence: true
    validates :count, numericality: { greater_than_or_equal_to: 0 }
    validates :issue_key,
              presence: true,
              inclusion: { in: -> (_record) { PallasTrade::CatalogHealth::Issues::KEYS } }
  end
end
