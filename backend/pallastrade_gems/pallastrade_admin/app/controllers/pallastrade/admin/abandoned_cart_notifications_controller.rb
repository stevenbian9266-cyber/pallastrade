# frozen_string_literal: true

module PallasTrade
  module Admin
    # Admin view of abandoned-cart recovery notifications (P0-3, 2026-08-18).
    # Admins can review sent notifications and trigger a scan on demand.
    class AbandonedCartNotificationsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Abandoned Cart Notifications

      # POST /admin/abandoned_cart_notifications/run — enqueue a scan for this store
      def run
        PallasTrade::AbandonedCarts::SendNotificationsJob.perform_later(store_id: current_store.id)
        flash[:success] = PallasTrade.t('admin.abandoned_cart_notifications.scan_started')
        redirect_to PallasTrade.admin_abandoned_cart_notifications_path
      end

      private

      def model_class
        PallasTrade::AbandonedCartNotification
      end

      def scope
        current_store.abandoned_cart_notifications
      end

      def object_name
        'abandoned_cart_notification'
      end

      def location_after_destroy
        PallasTrade.admin_abandoned_cart_notifications_path
      end
    end
  end
end
