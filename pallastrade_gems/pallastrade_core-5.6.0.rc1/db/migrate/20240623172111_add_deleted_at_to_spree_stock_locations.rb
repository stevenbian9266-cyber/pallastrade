class AddDeletedAtToSpreeStockLocations < ActiveRecord::Migration[6.1]
  def change
    add_column :PALLASTRADE_stock_locations, :deleted_at, :datetime, if_not_exists: true
    add_index :pallastrade_stock_locations, :deleted_at, if_not_exists: true
  end
end
