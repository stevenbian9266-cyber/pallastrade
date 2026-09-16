# frozen_string_literal: true

# D-3 切片1（PRD-20260916-catalog-d3-product-merge FR-009）—— 商品合并台账。
#
# 为什么需要这张表：合并必须**可撤销** —— 撤销要知道「当时到底搬了哪些行」。
# 逐条 id 清单放不进商品元数据，也无法查询，所以合并本身成为一条可审计的事实。
#
# 唯一性用 **partial unique**（`WHERE undone_at IS NULL`）表达：
# 「同一个被合并商品同时只能有一条未撤销的合并」—— 撤销之后重新合并是合法流程
# （既有先例：pallastrade_stock_reservations 的 `WHERE state='reserved'`）。
#
# 只新增表/索引，不改任何既有列。
class CreatePallasTradeProductMerges < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_product_merges do |t|
      t.bigint :store_id, null: false
      t.bigint :survivor_id, null: false
      t.bigint :absorbed_id, null: false
      t.string :actor_label
      t.string :actor_type
      t.bigint :actor_id
      # 逐条迁移清单（variants/master_stock/reviews/media/classifications/promotions → [id]）
      t.jsonb :moved, default: {}, null: false
      # 每段 { move: n, skip: n }，供报告与撤销前校验
      t.jsonb :counts, default: {}, null: false
      # [{ section, id, label, reason }]
      t.jsonb :skips, default: [], null: false
      # 本次合并建立的 redirect id（可多条：按店铺语言/国家前缀）
      t.jsonb :redirect_ids, default: [], null: false
      # 合并前被合并商品的状态（撤销时按原状态恢复，而不是一律 activate）
      t.string :absorbed_status_before
      t.datetime :undone_at
      t.string :undone_by_label
      t.timestamps
    end

    add_index :pallastrade_product_merges, %i[store_id absorbed_id],
              unique: true, where: 'undone_at IS NULL', name: 'idx_product_merges_active_absorbed'
    add_index :pallastrade_product_merges, %i[store_id survivor_id]
    add_index :pallastrade_product_merges, :absorbed_id
  end
end
