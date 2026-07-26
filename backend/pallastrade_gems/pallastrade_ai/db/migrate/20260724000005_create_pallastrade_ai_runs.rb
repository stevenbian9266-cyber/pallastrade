# frozen_string_literal: true

class CreatePallasTradeAiRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_ai_runs do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.bigint :user_id
      t.string :capability_key
      t.string :capability_version
      t.string :provider_type
      t.bigint :provider_id
      t.bigint :model_id
      t.string :provider_model_id
      t.string :status, null: false, default: 'queued'
      t.string :mode, null: false, default: 'sync'
      t.string :unavailable_reason
      t.bigint :fallback_from_model_id
      t.string :prompt_key
      t.string :prompt_version
      t.string :input_schema_version
      t.string :output_schema_version
      t.string :input_digest
      t.string :idempotency_key
      t.jsonb :safe_parameters, default: {}
      t.string :provider_request_id
      t.bigint :input_tokens, default: 0
      t.bigint :cached_input_tokens, default: 0
      t.bigint :output_tokens, default: 0
      t.bigint :reasoning_tokens, default: 0
      t.decimal :estimated_cost, precision: 12, scale: 6
      t.jsonb :pricing_snapshot, default: {}
      t.bigint :latency_ms
      t.integer :attempts, null: false, default: 0
      t.string :error_code
      t.string :error_message
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :pallastrade_ai_runs, %i[store_id created_at], name: 'idx_ai_runs_on_store_and_created_at'
    add_index :pallastrade_ai_runs, :status
    add_index :pallastrade_ai_runs, :capability_key
    add_index :pallastrade_ai_runs, :provider_id
    add_index :pallastrade_ai_runs, :model_id
    add_index :pallastrade_ai_runs, :user_id
    add_index :pallastrade_ai_runs, :error_code
    add_index :pallastrade_ai_runs, :mode
    add_index :pallastrade_ai_runs, %i[store_id idempotency_key], unique: true, name: 'idx_ai_runs_on_store_and_idempotency', where: 'idempotency_key IS NOT NULL'
  end
end
