module PallasTrade
  module Api
    module V2
      module Platform
        class RolesController < ResourceController
          private

          def model_class
            PallasTrade::Role
          end

          def resource_serializer
            PallasTrade.api.platform_role_serializer
          end
        end
      end
    end
  end
end
