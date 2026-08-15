# frozen_string_literal: true

# Email send log — one row per outgoing transactional email.
class CreatePallasTradeEmailLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_email_logs do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.string :mailer, null: false
      t.string :action, null: false
      t.string :to, null: false
      t.string :from
      t.string :subject
      t.string :status, default: 'sent', null: false
      t.text :error
      t.datetime :sent_at
      t.timestamps
    end

    add_index :pallastrade_email_logs, [:store_id, :sent_at]
    add_index :pallastrade_email_logs, [:store_id, :status]
  end
end
