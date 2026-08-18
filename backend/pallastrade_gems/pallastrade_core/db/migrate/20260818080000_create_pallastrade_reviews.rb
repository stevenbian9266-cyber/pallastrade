# frozen_string_literal: true

class CreatePallasTradeReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_reviews do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.references :product, null: false, foreign_key: { to_table: :pallastrade_products }
      t.references :user, null: false, foreign_key: { to_table: :pallastrade_users }
      t.integer :rating, null: false, default: 0
      t.string :title
      t.text :body
      t.string :status, null: false, default: 'pending'
      t.boolean :verified_purchase, null: false, default: false
      t.timestamps
    end

    add_index :pallastrade_reviews, [:product_id, :user_id], unique: true, name: 'index_pallastrade_reviews_on_product_and_user'
    add_index :pallastrade_reviews, [:store_id, :status]
  end
end
