module PallasTrade
  module Admin
    class StockMovementsController < ResourceController
      include TableConcern
      # 面包屑由导航自动推导（P3）：Products → Stock；本方法追加 Stock Movements

      before_action :add_breadcrumbs

      private

      def collection_default_sort
        'created_at desc'
      end

      def scope
        super.joins(stock_item: [:variant, :stock_location]).
          merge(current_store.variants.eligible).
          reorder('')
      end

      def collection_includes
        {
          stock_item: {
            stock_location: [],
            variant: [option_values: :option_type, product: [variants: [:images], master: [:images]], images: []]
          },
          originator: []
        }
      end

      def add_breadcrumbs
        add_breadcrumb PallasTrade.t(:stock_movements), PallasTrade.admin_stock_movements_path
      end
    end
  end
end
