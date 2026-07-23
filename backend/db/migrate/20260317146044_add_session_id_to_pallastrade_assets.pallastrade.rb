# This migration comes from pallastrade (originally 20250509143831)
class AddSessionIdToPallasTradeAssets < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_assets, :session_id, :string
  end
end
