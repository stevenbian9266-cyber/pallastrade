module PallasTrade
  module Api
    module V2
      module Platform
        class StateChangeSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :user, serializer: PallasTrade.api.platform_user_serializer
        end
      end
    end
  end
end
