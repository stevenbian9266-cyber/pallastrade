class RenameColumnAccessHashToToken < ActiveRecord::Migration[5.2]
  def change
    if table_exists?(:pallastrade_wishlists)
      rename_column(:pallastrade_wishlists, :access_hash, :token) if column_exists?(:pallastrade_wishlists, :access_hash)
      add_reference(:pallastrade_wishlists, :store, index: true) unless column_exists?(:pallastrade_wishlists, :store_id)
    end
  end
end
