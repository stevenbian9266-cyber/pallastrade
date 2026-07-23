class RenameDataFeedsColumnProviderToType < ActiveRecord::Migration[6.1]
  def change
    rename_column :pallastrade_data_feeds, :provider, :type
  end
end
