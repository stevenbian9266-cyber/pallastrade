# This migration comes from pallastrade (originally 20210921070815)
class RenamePallasTradeWishedProductsToPallasTradeWishedItems < ActiveRecord::Migration[5.2]
  def change
    rename_table :pallastrade_wished_products, :pallastrade_wished_items
  end
end
