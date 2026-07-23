class AddCounterCachesToPallasTradeProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :pallastrade_products, :variant_count, :integer, default: 0, null: false, if_not_exists: true
    add_column :pallastrade_products, :classification_count, :integer, default: 0, null: false, if_not_exists: true

    add_index :pallastrade_products, :variant_count, if_not_exists: true
    add_index :pallastrade_products, :classification_count, if_not_exists: true
  end
end
