class AddSessionIdToPallasTradeAssets < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_assets, :session_id, :string
  end
end
