# frozen_string_literal: true

# P0-3 Abandoned-cart recovery (2026-08-18):
# - track last cart activity on orders for abandoned-cart detection
# - store one notification row per (cart, email) so recovery mailers are idempotent
class AddLastActivityAndCreateAbandonedCartNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_orders, :last_activity_at, :datetime
    add_index :pallastrade_orders, :last_activity_at

    create_table :pallastrade_abandoned_cart_notifications do |t|
      t.references :store, null: false, foreign_key: { to_table: :pallastrade_stores }
      t.references :cart, null: false, foreign_key: { to_table: :pallastrade_orders }
      t.string :email, null: false
      t.datetime :sent_at
      t.timestamps
    end

    add_index :pallastrade_abandoned_cart_notifications, [:cart_id, :email], unique: true,
              name: 'index_abandoned_cart_notifications_on_cart_and_email'
  end
end
