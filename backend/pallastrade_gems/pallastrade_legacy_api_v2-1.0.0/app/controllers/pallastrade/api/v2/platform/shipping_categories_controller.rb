module PallasTrade
  module Api
    module V2
      module Platform
        class ShippingCategoriesController < ResourceController
          private

          def model_class
            PallasTrade::ShippingCategory
          end

          def resource_serializer
            PallasTrade.api.platform_shipping_category_serializer
          end
        end
      end
    end
  end
end
