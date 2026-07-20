class RenameDataFeedTableColumns < ActiveRecord::Migration[6.1]
  def change
    rename_column :PALLASTRADE_data_feeds, :PALLASTRADE_store_id, :store_id
    rename_column :PALLASTRADE_data_feeds, :enabled, :active
    rename_column :PALLASTRADE_data_feeds, :uuid, :slug
  end
end
