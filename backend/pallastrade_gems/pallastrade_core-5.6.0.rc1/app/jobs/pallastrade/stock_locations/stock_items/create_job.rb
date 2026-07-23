module PallasTrade
  module StockLocations
    module StockItems
      class CreateJob < PallasTrade::BaseJob
        queue_as PallasTrade.queues.stock_location_stock_items

        def perform(stock_location)
          PallasTrade::StockLocations::StockItems::Create.call(stock_location: stock_location)
        end
      end
    end
  end
end
