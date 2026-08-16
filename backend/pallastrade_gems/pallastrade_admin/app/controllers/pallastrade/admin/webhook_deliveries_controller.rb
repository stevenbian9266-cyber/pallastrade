# frozen_string_literal: true

module PallasTrade
  module Admin
    class WebhookDeliveriesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      # 嵌套资源：add_breadcrumbs 手写 父级(Webhook Endpoint) + 本页 crumb，跳过自动推导（P5）
      self.skip_breadcrumb_derivation = true

      helper 'pallastrade/admin/webhook_endpoints'

      belongs_to 'pallastrade/webhook_endpoint'

      before_action :add_breadcrumbs

      def redeliver
        load_resource
        authorize! :update, @object.webhook_endpoint
        new_delivery = @object.redeliver!
        flash[:success] = PallasTrade.t('admin.webhook_deliveries.redelivered')
        redirect_back(fallback_location: PallasTrade.admin_webhook_endpoint_webhook_delivery_path(@object.webhook_endpoint, new_delivery))
      end

      private

      def add_breadcrumbs
        if @webhook_endpoint.present?
          add_breadcrumb PallasTrade.t(:webhook_endpoints), PallasTrade.admin_webhook_endpoint_path(@webhook_endpoint)
          add_breadcrumb PallasTrade.t(:webhook_deliveries), PallasTrade.admin_webhook_endpoint_webhook_deliveries_path(@webhook_endpoint)
        else
          add_breadcrumb PallasTrade.t(:webhook_endpoints), :admin_webhook_endpoints_path
          add_breadcrumb PallasTrade.t(:webhook_deliveries)
        end
      end

      def collection_default_sort
        'created_at desc'
      end
    end
  end
end
