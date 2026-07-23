# This migration comes from pallastrade (originally 20260508175303)
class AddPickupToPallasTradeStockLocations < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_stock_locations, :kind, :string, null: false, default: 'warehouse'
    add_column :pallastrade_stock_locations, :pickup_enabled, :boolean, null: false, default: false
    add_column :pallastrade_stock_locations, :pickup_stock_policy, :string, null: false, default: 'local'
    add_column :pallastrade_stock_locations, :pickup_ready_in_minutes, :integer
    add_column :pallastrade_stock_locations, :pickup_instructions, :text

    add_index :pallastrade_stock_locations, :pickup_enabled
    add_index :pallastrade_stock_locations, :kind
  end
end
