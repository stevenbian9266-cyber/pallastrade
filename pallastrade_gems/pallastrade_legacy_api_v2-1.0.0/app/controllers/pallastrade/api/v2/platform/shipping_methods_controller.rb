module PallasTrade
  module Api
    module V2
      module Platform
        class ShippingMethodsController < ResourceController
          private

          def model_class
            PallasTrade::ShippingMethod
          end

          def pallastrade_permitted_attributes
            super + [
              {
                shipping_category_ids: [],
                calculator_attributes: {}
              }
            ]
          end

          def resource_serializer
            PallasTrade.api.platform_shipping_method_serializer
          end
        end
      end
    end
  end
end
