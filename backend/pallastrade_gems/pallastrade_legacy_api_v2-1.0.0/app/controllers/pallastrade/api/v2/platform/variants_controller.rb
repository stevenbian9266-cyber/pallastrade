module PallasTrade
  module Api
    module V2
      module Platform
        class VariantsController < ResourceController
          private

          def model_class
            PallasTrade::Variant
          end

          def pallastrade_permitted_attributes
            super + [:option_value_ids, :price, :currency]
          end

          def resource_serializer
            PallasTrade.api.platform_variant_serializer
          end
        end
      end
    end
  end
end
