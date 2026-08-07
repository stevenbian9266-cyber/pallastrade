# frozen_string_literal: true

class CreatePallasTradeAIModels < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_ai_models do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.references :provider, null: false, foreign_key: { to_table: :pallastrade_integrations }
      t.string :name, null: false
      t.string :provider_model_id, null: false
      t.string :kind, null: false, default: 'text'
      t.boolean :active, null: false, default: false
      t.boolean :built_in, null: false, default: false
      t.string :catalog_version
      t.jsonb :capabilities, default: []
      t.jsonb :default_parameters, default: {}
      t.integer :position
      t.timestamps
    end

    add_index :pallastrade_ai_models, %i[provider_id provider_model_id], unique: true, name: 'idx_ai_models_on_provider_and_model_id'
    add_index :pallastrade_ai_models, %i[store_id provider_id]
    add_index :pallastrade_ai_models, :active
    add_index :pallastrade_ai_models, :kind
  end
end
