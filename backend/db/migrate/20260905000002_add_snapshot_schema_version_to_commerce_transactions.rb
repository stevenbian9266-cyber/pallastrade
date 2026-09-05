# frozen_string_literal: true

# INV-P3-2 (PRD-20260905-shipping-库存事务集成与预留生命周期-p3-...):
# Transaction Snapshot schema 版本化 —— 新 Transaction 写 V2（含 inventory demand evidence），
# 历史 V1 snapshot 保持 immutable（不回溯）。默认 1 兼容存量行。
class AddSnapshotSchemaVersionToCommerceTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_commerce_transactions, :snapshot_schema_version, :integer,
               null: false, default: 1
  end
end
