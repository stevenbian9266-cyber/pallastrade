# This migration comes from pallastrade (originally 20250527134027)
class AddCompanyToPallasTradeStockLocations < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_stock_locations, :company, :string, if_not_exists: true
  end
end
