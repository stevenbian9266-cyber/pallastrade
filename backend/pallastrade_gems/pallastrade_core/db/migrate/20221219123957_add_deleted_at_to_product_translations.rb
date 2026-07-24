class AddDeletedAtToProductTranslations < ActiveRecord::Migration[6.1]
  def change
    add_column :pallastrade_product_translations, :deleted_at, :datetime
    add_index :pallastrade_product_translations, :deleted_at
  end
end
