# frozen_string_literal: true

class CreatePallasTradeAllowedOrigins < ActiveRecord::Migration[7.2]
  def change
    create_table :pallastrade_allowed_origins do |t|
      t.references :store, null: false
      t.string :origin, null: false
      t.timestamps
    end

    add_index :pallastrade_allowed_origins, [:store_id, :origin], unique: true,
              name: 'index_pallastrade_allowed_origins_on_store_id_and_origin'
  end
end
