module PallasTrade
  module Admin
    class CheckoutsController < ResourceController
      include PallasTrade::Admin::OrdersFiltersHelper
      include PallasTrade::Admin::TableConcern

      # 面包屑由导航自动推导（P3）：Orders → Draft Orders
      before_action :load_user, only: [:index]

      def index
        @orders = @collection
      end

      private

      def scope
        current_store.checkouts.accessible_by(current_ability, :index).includes(collection_includes)
      end

      def collection_default_sort
        'created_at desc'
      end

      def collection_includes
        { user: [] }
      end

      def edit_object_url(object, options = {})
        PallasTrade.admin_order_path(object, options)
      end
    end
  end
end
