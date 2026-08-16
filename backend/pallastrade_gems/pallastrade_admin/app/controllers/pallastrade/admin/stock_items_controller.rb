module PallasTrade
  module Admin
    class StockItemsController < ResourceController
      include TableConcern
      # 面包屑由导航自动推导（P6）：Products → Stock → Stock Items（stock_tabs 节点）

      private

      def update_turbo_stream_enabled?
        true
      end

      def scope
        super.joins(:variant).where(pallastrade_variants: { track_inventory: true }).merge(current_store.variants.eligible).reorder('')
      end

      def collection_includes
        {
          stock_location: [],
          variant: [option_values: :option_type, product: [variants: [:images], master: [:images]], images: []]
        }
      end

      def permitted_resource_params
        params.require(:stock_item).permit(permitted_stock_item_attributes)
      end
    end
  end
end
