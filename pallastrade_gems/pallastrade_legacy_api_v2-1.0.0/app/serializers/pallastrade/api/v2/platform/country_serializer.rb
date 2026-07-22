module PallasTrade
  module Api
    module V2
      module Platform
        class CountrySerializer < BaseSerializer
          include ResourceSerializerConcern

          has_many :states, serializer: PallasTrade.api.platform_state_serializer
        end
      end
    end
  end
end
