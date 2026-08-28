# frozen_string_literal: true

# Order lifecycle P8 (2026-08-28): user blacklist timestamp for checkout preflight.
# Nullable — existing users are untouched; reversible.
class AddBlacklistedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :pallastrade_users, :blacklisted_at, :datetime, null: true
  end
end
