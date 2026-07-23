module PallasTrade
  module Api
    module V2
      module Platform
        class CountriesController < ResourceController
          private

          def model_class
            PallasTrade::Country
          end

          def scope_includes
            [:states, :zones]
          end

          def resource_serializer
            PallasTrade.api.platform_country_serializer
          end
        end
      end
    end
  end
end
