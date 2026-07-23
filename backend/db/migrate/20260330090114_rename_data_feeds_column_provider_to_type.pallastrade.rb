# This migration comes from pallastrade (originally 20230512094803)
class RenameDataFeedsColumnProviderToType < ActiveRecord::Migration[6.1]
  def change
    rename_column :pallastrade_data_feeds, :provider, :type
  end
end
