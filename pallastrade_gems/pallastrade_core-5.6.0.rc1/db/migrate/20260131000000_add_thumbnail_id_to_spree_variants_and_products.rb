class AddThumbnailIdToSpreeVariantsAndProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :PALLASTRADE_variants, :thumbnail_id, :bigint, if_not_exists: true
    add_column :PALLASTRADE_products, :thumbnail_id, :bigint, if_not_exists: true

    add_index :pallastrade_variants, :thumbnail_id, if_not_exists: true
    add_index :pallastrade_products, :thumbnail_id, if_not_exists: true
  end
end
