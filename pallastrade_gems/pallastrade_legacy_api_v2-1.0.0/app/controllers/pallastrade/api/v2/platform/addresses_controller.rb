module PallasTrade
  module Api
    module V2
      module Platform
        class AddressesController < ResourceController
          private

          def model_class
            PallasTrade::Address
          end

          def scope_includes
            [:country, :state, :user]
          end

          def resource_serializer
            PallasTrade.api.platform_address_serializer
          end
        end
      end
    end
  end
end
