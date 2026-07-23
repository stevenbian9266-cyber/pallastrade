# frozen_string_literal: true

class ImprovePallasTradeWebhooks < ActiveRecord::Migration[7.2]
  def change
    # Endpoint name + auto-disable tracking
    add_column :pallastrade_webhook_endpoints, :name, :string
    add_column :pallastrade_webhook_endpoints, :disabled_reason, :string
    add_column :pallastrade_webhook_endpoints, :disabled_at, :datetime

    # Event ID for delivery deduplication
    add_column :pallastrade_webhook_deliveries, :event_id, :string
    add_index :pallastrade_webhook_deliveries, [:webhook_endpoint_id, :event_id],
              unique: true,
              where: 'event_id IS NOT NULL',
              name: 'index_pallastrade_webhook_deliveries_on_endpoint_and_event'
  end
end
