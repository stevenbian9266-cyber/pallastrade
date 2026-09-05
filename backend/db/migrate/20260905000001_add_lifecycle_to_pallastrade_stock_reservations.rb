# frozen_string_literal: true

# INV-P3-1 (PRD-20260905-shipping-库存事务集成与预留生命周期-p3-...):
# StockReservation 生命周期状态化 —— RESERVED/COMMITTED/RELEASED/EXPIRED。
# Release/Expire 由硬删除改为状态流转，保留审计/历史证据；新增 transaction ownership（可空）。
# 见 docs/research/RESEARCH-20260905-inv-p3-0-inventory-semantic-freeze.md §16。
class AddLifecycleToPallasTradeStockReservations < ActiveRecord::Migration[8.1]
  def up
    add_column :pallastrade_stock_reservations, :state, :string, null: false, default: 'reserved'
    add_column :pallastrade_stock_reservations, :reserved_at, :datetime
    add_column :pallastrade_stock_reservations, :committed_at, :datetime
    add_column :pallastrade_stock_reservations, :released_at, :datetime
    add_column :pallastrade_stock_reservations, :expired_at, :datetime
    add_column :pallastrade_stock_reservations, :release_reason, :string
    add_reference :pallastrade_stock_reservations, :commerce_transaction,
                  foreign_key: { to_table: :pallastrade_commerce_transactions },
                  index: true

    # 兼容既有活跃唯一约束：仅 RESERVED 行唯一；历史终态行（COMMITTED/RELEASED/EXPIRED）
    # 允许多版本保留（Postgres partial unique index）。
    remove_index :pallastrade_stock_reservations, name: 'idx_stock_reservations_item_line_item'
    add_index :pallastrade_stock_reservations, %i[stock_item_id line_item_id],
              unique: true, where: "state = 'reserved'",
              name: 'idx_stock_reservations_active_reserved_unique'

    # active reservation / Quantifier 热路径索引：按 stock_item 查 state=reserved 未过期
    add_index :pallastrade_stock_reservations, %i[stock_item_id state expires_at],
              name: 'idx_stock_reservations_item_state_expires'

    # Backfill：历史行迁移到状态模型。
    # 1) 所有存量行视为当时创建即预留 → reserved_at = created_at
    execute <<~SQL
      UPDATE pallastrade_stock_reservations
         SET reserved_at = created_at
       WHERE reserved_at IS NULL
    SQL
    # 2) 已过 TTL 的行不再占用 ATS → 直接落 EXPIRED（保留历史，不删除）
    execute <<~SQL
      UPDATE pallastrade_stock_reservations
         SET state = 'expired', expired_at = expires_at
       WHERE state = 'reserved' AND expires_at <= NOW()
    SQL
  end

  def down
    # 说明：down 无法还原 backfill 已转 EXPIRED 的行语义（数据单向迁移），仅回滚 schema。
    remove_index :pallastrade_stock_reservations, name: 'idx_stock_reservations_active_reserved_unique'
    remove_index :pallastrade_stock_reservations, name: 'idx_stock_reservations_item_state_expires'
    add_index :pallastrade_stock_reservations, %i[stock_item_id line_item_id],
              unique: true, name: 'idx_stock_reservations_item_line_item'
    remove_reference :pallastrade_stock_reservations, :commerce_transaction
    remove_column :pallastrade_stock_reservations, :release_reason
    remove_column :pallastrade_stock_reservations, :expired_at
    remove_column :pallastrade_stock_reservations, :released_at
    remove_column :pallastrade_stock_reservations, :committed_at
    remove_column :pallastrade_stock_reservations, :reserved_at
    remove_column :pallastrade_stock_reservations, :state
  end
end
