module PallasTrade
  module Api
    module V2
      module Platform
        class StockTransferSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :destination_location, serializer: PallasTrade.api.platform_stock_location_serializer
          belongs_to :source_location, serializer: PallasTrade.api.platform_stock_location_serializer
          has_many :stock_movements, serializer: PallasTrade.api.platform_stock_movement_serializer
        end
      end
    end
  end
end
