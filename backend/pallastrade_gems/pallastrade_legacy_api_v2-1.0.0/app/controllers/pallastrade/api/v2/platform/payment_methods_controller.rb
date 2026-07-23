module PallasTrade
  module Api
    module V2
      module Platform
        class PaymentMethodsController < ResourceController
          private

          def model_class
            PallasTrade::PaymentMethod
          end

          def pallastrade_permitted_attributes
            preferred_attributes = []

            if action_name == 'update'
              resource.defined_preferences.each do |preference|
                preferred_attributes << "preferred_#{preference}".to_sym
              end
            end

            super + preferred_attributes
          end

          def resource_serializer
            PallasTrade.api.platform_payment_method_serializer
          end
        end
      end
    end
  end
end
