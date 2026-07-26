# frozen_string_literal: true

class CreatePallasTradeAiArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_ai_artifacts do |t|
      t.references :run, null: false, foreign_key: { to_table: :pallastrade_ai_runs }
      t.string :kind, null: false
      t.string :schema_version
      t.jsonb :payload
      t.string :content_type
      t.string :checksum
      t.timestamps
    end

    add_index :pallastrade_ai_artifacts, :kind
  end
end
