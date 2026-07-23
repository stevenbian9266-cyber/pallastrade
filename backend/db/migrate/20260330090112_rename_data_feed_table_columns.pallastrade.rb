# This migration comes from pallastrade (originally 20230415160828)
class RenameDataFeedTableColumns < ActiveRecord::Migration[6.1]
  def change
    rename_column :pallastrade_data_feeds, :pallastrade_store_id, :store_id
    rename_column :pallastrade_data_feeds, :enabled, :active
    rename_column :pallastrade_data_feeds, :uuid, :slug
  end
end
