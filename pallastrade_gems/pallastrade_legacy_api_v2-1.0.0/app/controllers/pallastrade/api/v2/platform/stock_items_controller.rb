module PallasTrade
  module Api
    module V2
      module Platform
        class StockItemsController < ResourceController
          private

          def model_class
            PallasTrade::StockItem
          end

          def scope_includes
            [:variant, :stock_location]
          end

          def resource_serializer
            PallasTrade.api.platform_stock_item_serializer
          end
        end
      end
    end
  end
end
