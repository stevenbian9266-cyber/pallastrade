module PallasTrade
  module Api
    module V2
      module Platform
        class AddressSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :country, serializer: PallasTrade.api.platform_country_serializer
          belongs_to :state, serializer: PallasTrade.api.platform_state_serializer
          belongs_to :user, serializer: PallasTrade.api.platform_user_serializer
        end
      end
    end
  end
end
