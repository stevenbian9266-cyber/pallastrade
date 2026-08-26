# frozen_string_literal: true

# Order lifecycle P1 (2026-08-26): combined-payment carrier table.
# One PaymentCombination = one checkout payment covering N member orders.
# Decoupled from the parent/child order structure (can span parents).
class CreatePallasTradePaymentCombinations < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_payment_combinations do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.references :customer, null: false, foreign_key: { to_table: :pallastrade_users }
      t.string :currency, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false, default: 0
      t.string :status, null: false, default: 'pending'
      t.datetime :expires_at
      t.datetime :completed_at
      t.jsonb :public_metadata, default: {}
      t.jsonb :private_metadata, default: {}
      t.timestamps
    end
    add_index :pallastrade_payment_combinations, :status
  end
end
