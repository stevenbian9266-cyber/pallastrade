class RenameDataFeedSettingsTable < ActiveRecord::Migration[6.1]
  def change
    rename_table :pallastrade_data_feed_settings, :pallastrade_data_feeds
  end
end
