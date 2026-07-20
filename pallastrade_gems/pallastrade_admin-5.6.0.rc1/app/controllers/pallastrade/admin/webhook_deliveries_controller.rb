# frozen_string_literal: true

module PallasTrade
  module Admin
    class WebhookDeliveriesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      helper 'spree/admin/webhook_endpoints'

      belongs_to 'spree/webhook_endpoint'

      def redeliver
        load_resource
        authorize! :update, @object.webhook_endpoint
        new_delivery = @object.redeliver!
        flash[:success] = PallasTrade.t('admin.webhook_deliveries.redelivered')
        redirect_back(fallback_location: PallasTrade.admin_webhook_endpoint_webhook_delivery_path(@object.webhook_endpoint, new_delivery))
      end

      private

      def collection_default_sort
        'created_at desc'
      end
    end
  end
end
