# frozen_string_literal: true

# Back-in-stock notifications — customers leave an email on an out-of-stock
# variant and get notified when the product is back in stock.
class CreatePallasTradeBackInStockSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_back_in_stock_subscriptions do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.references :product, null: false, foreign_key: { to_table: :pallastrade_products }
      t.string :email, null: false
      t.string :status, default: 'active', null: false
      t.timestamps
    end

    add_index :pallastrade_back_in_stock_subscriptions, [:product_id, :email], unique: true, name: 'index_bis_subscriptions_on_product_and_email'
  end
end
