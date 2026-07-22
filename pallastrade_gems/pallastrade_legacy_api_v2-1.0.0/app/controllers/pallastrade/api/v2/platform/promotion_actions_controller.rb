module PallasTrade
  module Api
    module V2
      module Platform
        class PromotionActionsController < ResourceController
          include ::PallasTrade::Api::V2::Platform::PromotionCalculatorParams

          private

          def model_class
            PallasTrade::PromotionAction
          end

          def scope_includes
            [:promotion]
          end

          def pallastrade_permitted_attributes
            conditional_params = action_name == 'update' ? [:id] : []

            super + [{
              promotion_action_line_items_attributes: PallasTrade::PromotionActionLineItem.json_api_permitted_attributes.concat(conditional_params),
              calculator_attributes: PallasTrade::Calculator.json_api_permitted_attributes.concat(conditional_params, calculator_params)
            }]
          end

          def resource_serializer
            PallasTrade.api.platform_promotion_action_serializer
          end
        end
      end
    end
  end
end
