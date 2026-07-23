# This migration comes from pallastrade (originally 20250113180019)
class AddPreferencesToPallasTradeStores < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_stores, :preferences, :text, if_not_exists: true
  end
end
