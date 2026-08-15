# frozen_string_literal: true

module PallasTrade
  module Admin
    # Read-only admin view of back-in-stock subscriptions. Subscriptions are
    # created by customers from the storefront; admins can review and delete.
    class BackInStockSubscriptionsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      private

      def model_class
        PallasTrade::BackInStockSubscription
      end

      def scope
        current_store.back_in_stock_subscriptions
      end

      def object_name
        'back_in_stock_subscription'
      end

      def location_after_destroy
        PallasTrade.admin_back_in_stock_subscriptions_path
      end
    end
  end
end
