# This migration comes from pallastrade (originally 20260120120000)
class AddImageCountToPallasTradeVariants < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_variants, :image_count, :integer, default: 0, null: false, if_not_exists: true
    add_column :pallastrade_products, :total_image_count, :integer, default: 0, null: false, if_not_exists: true

    add_index :pallastrade_variants, :image_count, if_not_exists: true
    add_index :pallastrade_products, :total_image_count, if_not_exists: true
  end
end
