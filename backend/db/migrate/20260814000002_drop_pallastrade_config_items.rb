# frozen_string_literal: true

# Retire the Config Center module (2026-08-14): drop the config_items table.
# Configuration returns to .env files (AI-coding friendly) + scan-secrets guard.
class DropPallasTradeConfigItems < ActiveRecord::Migration[8.1]
  def change
    drop_table :pallastrade_config_items, if_exists: true
  end
end
