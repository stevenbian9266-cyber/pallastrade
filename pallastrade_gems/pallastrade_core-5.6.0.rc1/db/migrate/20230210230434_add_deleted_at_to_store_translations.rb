class AddDeletedAtToStoreTranslations < ActiveRecord::Migration[6.1]
  def change
    add_column :PALLASTRADE_store_translations, :deleted_at, :datetime
    add_index :pallastrade_store_translations, :deleted_at
  end
end
