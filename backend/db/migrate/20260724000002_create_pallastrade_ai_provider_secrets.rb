# frozen_string_literal: true

class CreatePallasTradeAIProviderSecrets < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_ai_provider_secrets do |t|
      t.references :integration, null: false, foreign_key: { to_table: :pallastrade_integrations }, index: { unique: true }
      t.text :credentials, null: false # Encrypted via Active Record Encryption
      t.string :key_hint, null: false, default: ''
      t.string :encryption_key_version
      t.datetime :rotated_at
      t.timestamps
    end

    add_index :pallastrade_ai_provider_secrets, :encryption_key_version
  end
end
