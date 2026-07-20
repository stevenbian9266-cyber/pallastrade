module PallasTrade
  module StockLocations
    module StockItems
      class Create
        prepend PallasTrade::ServiceModule::Base

        def call(stock_location:, variants_scope: PallasTrade::Variant)
          prepared_stock_items = variants_scope.ids.map do |variant_id|
            Hash[
              'stock_location_id', stock_location.id,
              'variant_id', variant_id,
              'backorderable', stock_location.backorderable_default,
              'created_at', Time.current,
              'updated_at', Time.current
            ]
          end
          if prepared_stock_items.any?
            stock_location.stock_items.insert_all(prepared_stock_items)
            variants_scope.touch_all
          end
        end
      end
    end
  end
end
