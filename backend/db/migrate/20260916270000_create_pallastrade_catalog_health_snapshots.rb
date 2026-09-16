# frozen_string_literal: true

# G-7（PRD-20260916-catalog-health-trend-snapshot FR-001）—— Catalog Health 每日趋势快照。
#
# 为什么需要这张表：Catalog Health 工作台只有「当前计数」—— 它是一张待办清单，不是趋势线。
# 方案 §十六 的指标「Unresolved Catalog Health Issues」因此缺时间维度：能看到「现在有 37 个」，
# 却回答不了「治理在变好还是变差」。
#
# 设计要点：
# * **每日一行/issue**（而不是事后实时重算历史）：issue 的判定口径会随代码演进
#   （如 old_drafts 的 30 天阈值），历史必须按**当日口径**保存 —— 事后重算 = 篡改历史；
# * 唯一键 `(store_id, issue_key, captured_on)` 让**同日重跑幂等**：补跑/重跑不会产生重复行，
#   DB 约束比应用层判断可靠（既有先例：pallastrade_payment_risk_assessments 的 (order_id, evaluated_at)）；
# * 只新增表/索引，不改任何既有列。
class CreatePallasTradeCatalogHealthSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_catalog_health_snapshots do |t|
      t.bigint :store_id, null: false
      # PallasTrade::CatalogHealth::Issues::KEYS 之一；计数为 0 也留行（0 是事实，"没有行"是缺失）
      t.string :issue_key, null: false
      t.date :captured_on, null: false
      t.integer :count, null: false, default: 0
      t.timestamps
    end

    add_index :pallastrade_catalog_health_snapshots, %i[store_id issue_key captured_on],
              unique: true, name: 'idx_catalog_health_snapshots_daily'
    add_index :pallastrade_catalog_health_snapshots, %i[store_id captured_on]
  end
end
