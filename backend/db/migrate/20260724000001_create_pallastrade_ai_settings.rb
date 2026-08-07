# frozen_string_literal: true

class CreatePallasTradeAISettings < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_ai_settings do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }, index: { unique: true }
      t.boolean :active, null: false, default: false
      t.bigint :default_model_id
      t.boolean :fallback_enabled, null: false, default: false
      t.bigint :daily_request_limit
      t.bigint :daily_input_token_limit
      t.bigint :daily_output_token_limit
      t.decimal :daily_cost_limit, precision: 12, scale: 4
      t.integer :run_retention_days, null: false, default: 30
      t.string :content_logging_mode, null: false, default: 'none'
      t.timestamps
    end

    add_index :pallastrade_ai_settings, :default_model_id
  end
end
