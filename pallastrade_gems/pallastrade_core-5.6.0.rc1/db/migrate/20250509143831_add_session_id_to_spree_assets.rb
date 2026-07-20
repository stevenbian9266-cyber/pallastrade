class AddSessionIdToSpreeAssets < ActiveRecord::Migration[7.2]
  def change
    add_column :PALLASTRADE_assets, :session_id, :string
  end
end
