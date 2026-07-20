class RenameSpreeWishedProductsToSpreeWishedItems < ActiveRecord::Migration[5.2]
  def change
    rename_table :pallastrade_wished_products, :PALLASTRADE_wished_items
  end
end
