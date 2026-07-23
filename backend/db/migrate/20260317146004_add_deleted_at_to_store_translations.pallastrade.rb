# This migration comes from pallastrade (originally 20230210230434)
class AddDeletedAtToStoreTranslations < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_store_translations, :deleted_at, :datetime
    add_index :pallastrade_store_translations, :deleted_at
  end
end
