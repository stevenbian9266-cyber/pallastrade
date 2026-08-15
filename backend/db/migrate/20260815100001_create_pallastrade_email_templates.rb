# frozen_string_literal: true

# Email templates — editable transactional mail content per store.
# Admin-managed; falls back to code templates when no DB row exists.
class CreatePallasTradeEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_email_templates do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.string :key, null: false
      t.string :name, null: false
      t.string :subject, null: false
      t.text :body_html
      t.text :body_text
      t.text :placeholders
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :pallastrade_email_templates, [:store_id, :key], unique: true
  end
end
