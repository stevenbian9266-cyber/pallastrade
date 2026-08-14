# frozen_string_literal: true

class CreatePallasTradeConfigItems < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_config_items do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.string :key, null: false
      t.string :group, null: false, default: 'general'
      t.string :value_type, null: false, default: 'string'
      t.text :value # Plaintext lane (string/boolean/number)
      t.text :secret_value # Encrypted lane via Active Record Encryption
      t.string :key_hint, null: false, default: ''
      t.string :description
      t.string :default_value
      t.datetime :rotated_at
      t.timestamps
    end

    add_index :pallastrade_config_items, [:store_id, :key], unique: true
    add_index :pallastrade_config_items, :group
  end
end
