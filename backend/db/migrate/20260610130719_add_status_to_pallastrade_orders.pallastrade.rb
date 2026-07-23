# This migration comes from pallastrade (originally 20260429000003)
class AddStatusToPallasTradeOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_orders, :status, :string
    add_index :pallastrade_orders, :status
  end
end
