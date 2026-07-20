# frozen_string_literal: true

module PallasTrade
  module Admin
    class WebhookEndpointsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      helper 'spree/admin/webhook_endpoints'

      def test
        load_resource
        authorize! :update, @object
        begin
          @object.send_test!
          flash[:success] = PallasTrade.t('admin.webhook_endpoints.test_sent')
        rescue StandardError => e
          Rails.error.report(e, context: { webhook_endpoint_id: @object.id, url: @object.url })
          flash[:error] = PallasTrade.t('admin.webhook_endpoints.test_failed')
        end
        redirect_back(fallback_location: PallasTrade.admin_webhook_endpoint_path(@object))
      end

      private

      def permitted_resource_params
        params.require(:webhook_endpoint).permit(permitted_webhook_endpoint_attributes)
      end

      def location_after_save
        PallasTrade.admin_webhook_endpoint_path(@object)
      end

      def update_turbo_stream_enabled?
        true
      end
    end
  end
end
