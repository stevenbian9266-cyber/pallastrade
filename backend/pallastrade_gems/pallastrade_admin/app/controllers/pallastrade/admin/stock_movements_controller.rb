module PallasTrade
  module Admin
    class StockMovementsController < ResourceController
      include TableConcern
      # 面包屑由导航自动推导（P6）：Products → Stock → Stock Movements（stock_tabs 节点）

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
    end
  end
end
