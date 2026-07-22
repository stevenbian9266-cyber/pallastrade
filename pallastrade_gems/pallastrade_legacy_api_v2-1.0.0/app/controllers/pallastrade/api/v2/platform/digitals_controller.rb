module PallasTrade
  module Api
    module V2
      module Platform
        class DigitalsController < ResourceController
          private

          def model_class
            PallasTrade::Digital
          end

          def pallastrade_permitted_attributes
            super + [:attachment]
          end

          def resource_serializer
            PallasTrade.api.platform_digital_serializer
          end
        end
      end
    end
  end
end
