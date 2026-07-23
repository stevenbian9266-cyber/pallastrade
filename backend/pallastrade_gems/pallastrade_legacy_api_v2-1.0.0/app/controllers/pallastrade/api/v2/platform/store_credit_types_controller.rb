module PallasTrade
  module Api
    module V2
      module Platform
        class StoreCreditTypesController < ResourceController
          private

          def model_class
            PallasTrade::StoreCreditType
          end

          def resource_serializer
            PallasTrade.api.platform_store_credit_type_serializer
          end
        end
      end
    end
  end
end
