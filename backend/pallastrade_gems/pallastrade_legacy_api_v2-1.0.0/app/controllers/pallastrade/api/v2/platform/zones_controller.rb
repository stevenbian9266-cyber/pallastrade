module PallasTrade
  module Api
    module V2
      module Platform
        class ZonesController < ResourceController
          private

          def model_class
            PallasTrade::Zone
          end

          def scope_includes
            [:zone_members]
          end

          def resource_serializer
            PallasTrade.api.platform_zone_serializer
          end
        end
      end
    end
  end
end
