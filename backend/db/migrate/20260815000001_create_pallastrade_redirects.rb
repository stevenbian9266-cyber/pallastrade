# frozen_string_literal: true

# SEO 301 redirects — old URL → new URL mapping per store.
class CreatePallasTradeRedirects < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_redirects do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.string :from_path, null: false
      t.string :to_path, null: false
      t.integer :status_code, default: 301, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :pallastrade_redirects, [:store_id, :from_path], unique: true
  end
end
