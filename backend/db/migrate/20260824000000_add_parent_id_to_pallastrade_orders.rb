# PALLAS-CUSTOM: 父子单结构（PRD-20260824-checkout-正向订单-逆向订单链路重构或优化）
#
# Adds a self-referencing parent_id to orders so an order can be a parent order
# with N child orders (split result), or a single order (parent = child when
# parent_id is nil and it has no children).
class AddParentIdToPallasTradeOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_orders, :parent_id, :bigint
    add_index :pallastrade_orders, :parent_id
    add_foreign_key :pallastrade_orders, :pallastrade_orders, column: :parent_id
  end
end
