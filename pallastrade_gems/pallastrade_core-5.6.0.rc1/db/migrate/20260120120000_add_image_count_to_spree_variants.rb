class AddImageCountToSpreeVariants < ActiveRecord::Migration[7.2]
  def change
    add_column :PALLASTRADE_variants, :image_count, :integer, default: 0, null: false, if_not_exists: true
    add_column :PALLASTRADE_products, :total_image_count, :integer, default: 0, null: false, if_not_exists: true

    add_index :pallastrade_variants, :image_count, if_not_exists: true
    add_index :pallastrade_products, :total_image_count, if_not_exists: true
  end
end
