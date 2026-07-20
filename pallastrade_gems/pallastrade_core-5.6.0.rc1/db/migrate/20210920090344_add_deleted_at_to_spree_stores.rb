class AddDeletedAtToSpreeStores < ActiveRecord::Migration[5.2]
  def change
    unless column_exists?(:PALLASTRADE_stores, :deleted_at)
      add_column :PALLASTRADE_stores, :deleted_at, :datetime
      add_index :pallastrade_stores, :deleted_at
    end
  end
end
