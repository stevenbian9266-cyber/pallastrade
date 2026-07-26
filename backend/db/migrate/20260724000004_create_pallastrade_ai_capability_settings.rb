# frozen_string_literal: true

class CreatePallasTradeAiCapabilitySettings < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_ai_capability_settings do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.string :capability_key, null: false
      t.boolean :active, null: false, default: false
      t.bigint :primary_model_id
      t.bigint :fallback_model_id
      t.boolean :fallback_enabled, null: false, default: false
      t.jsonb :parameter_overrides, default: {}
      t.bigint :daily_request_limit
      t.bigint :daily_token_limit
      t.boolean :orphaned, null: false, default: false
      t.timestamps
    end

    add_index :pallastrade_ai_capability_settings, %i[store_id capability_key], unique: true, name: 'idx_ai_capability_settings_on_store_and_key'
    add_index :pallastrade_ai_capability_settings, :primary_model_id
    add_index :pallastrade_ai_capability_settings, :fallback_model_id
  end
end
