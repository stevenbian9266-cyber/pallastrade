module PallasTrade
  module Api
    module V2
      module Platform
        class StockLocationSerializer < BaseSerializer
          include ResourceSerializerConcern

          attributes :name
          belongs_to :country, serializer: PallasTrade.api.platform_country_serializer
        end
      end
    end
  end
end
