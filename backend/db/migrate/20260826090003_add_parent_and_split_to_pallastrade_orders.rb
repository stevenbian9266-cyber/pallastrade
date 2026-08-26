# frozen_string_literal: true

# Order lifecycle P1 (2026-08-26): parent/child order structure + combined-payment
# carrier FK on orders. All columns nullable — existing single orders are untouched.
class AddParentAndSplitToPallasTradeOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :pallastrade_orders, :parent, null: true,
                 foreign_key: { to_table: :pallastrade_orders }
    add_reference :pallastrade_orders, :split_from, null: true,
                 foreign_key: { to_table: :pallastrade_orders }
    add_reference :pallastrade_orders, :payment_combination, null: true,
                 foreign_key: { to_table: :pallastrade_payment_combinations }
  end
end
