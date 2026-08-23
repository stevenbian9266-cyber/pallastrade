# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
class CreatePallasTradePaymentGroups < ActiveRecord::Migration[7.2]
  def change
    create_table :pallastrade_payment_groups do |t|
      t.references :store, null: false, index: true
      t.references :customer, index: true
      t.decimal :amount, precision: 10, scale: 2, default: "0.0", null: false
      t.string :currency, null: false
      t.string :status, null: false, default: 'pending', index: true
      t.datetime :expires_at, index: true
      t.datetime :completed_at, index: true
      t.datetime :deleted_at, index: true
      t.timestamps
    end

    # Orders belong to at most one payment group (nullable — single-order path unchanged)
    add_reference :pallastrade_orders, :payment_group, index: true

    # Manual/auto split provenance: which order an order was split from (nullable)
    add_column :pallastrade_orders, :split_from_id, :bigint
    add_index :pallastrade_orders, :split_from_id

    # Payment sessions may cover a whole group (nullable — single-order path unchanged)
    add_reference :pallastrade_payment_sessions, :payment_group, index: true
  end
end
