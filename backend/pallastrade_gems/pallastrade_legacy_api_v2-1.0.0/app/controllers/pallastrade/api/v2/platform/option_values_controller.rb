module PallasTrade
  module Api
    module V2
      module Platform
        class OptionValuesController < ResourceController
          private

          def model_class
            PallasTrade::OptionValue
          end

          def scope_includes
            [:option_type]
          end

          def resource_serializer
            PallasTrade.api.platform_option_value_serializer
          end
        end
      end
    end
  end
end
