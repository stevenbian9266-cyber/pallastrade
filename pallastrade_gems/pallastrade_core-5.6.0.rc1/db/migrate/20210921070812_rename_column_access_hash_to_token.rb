class RenameColumnAccessHashToToken < ActiveRecord::Migration[5.2]
  def change
    if table_exists?(:PALLASTRADE_wishlists)
      rename_column(:PALLASTRADE_wishlists, :access_hash, :token) if column_exists?(:PALLASTRADE_wishlists, :access_hash)
      add_reference(:PALLASTRADE_wishlists, :store, index: true) unless column_exists?(:PALLASTRADE_wishlists, :store_id)
    end
  end
end
