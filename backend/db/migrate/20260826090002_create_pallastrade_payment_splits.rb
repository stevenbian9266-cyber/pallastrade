# frozen_string_literal: true

# Order lifecycle P1 (2026-08-26): per-order share of a combined payment.
# One row per member order; authorized/captured/refunded amounts are the
# authoritative split for the child order's paid/refundable totals.
class CreatePallasTradePaymentSplits < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_payment_splits do |t|
      t.references :payment_combination, null: false,
                   foreign_key: { to_table: :pallastrade_payment_combinations }
      t.references :order, null: false, foreign_key: { to_table: :pallastrade_orders }
      t.references :payment, null: false, foreign_key: { to_table: :pallastrade_payments }
      t.string :currency, null: false
      t.decimal :authorized_amount, precision: 10, scale: 2, null: false, default: 0
      t.decimal :captured_amount, precision: 10, scale: 2, null: false, default: 0
      t.decimal :refunded_amount, precision: 10, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :pallastrade_payment_splits, [:payment_combination_id, :order_id],
              unique: true, name: 'index_pt_payment_splits_on_combination_and_order'
  end
end
