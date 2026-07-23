module PallasTrade
  module Api
    module V2
      module Platform
        class StateSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :country, serializer: PallasTrade.api.platform_country_serializer
        end
      end
    end
  end
end
