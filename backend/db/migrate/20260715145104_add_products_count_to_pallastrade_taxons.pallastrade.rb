# This migration comes from pallastrade (originally 20260627000001)
class AddProductsCountToPallasTradeTaxons < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_taxons, :products_count, :integer, default: 0, null: false, if_not_exists: true
    add_index :pallastrade_taxons, :products_count, if_not_exists: true
  end
end
