module PallasTrade
  module Api
    module V2
      module Platform
        class PromotionsController < ResourceController
          include ::PallasTrade::Api::V2::Platform::PromotionRuleParams
          include ::PallasTrade::Api::V2::Platform::PromotionCalculatorParams

          private

          def model_class
            PallasTrade::Promotion
          end

          def scope_includes
            [:promotion_category, :promotion_rules, :promotion_actions]
          end

          def pallastrade_permitted_attributes
            conditional_params = action_name == 'update' ? [:id] : []

            super + [{ promotion_actions_attributes: PallasTrade::PromotionAction.json_api_permitted_attributes.concat(conditional_params) + [{
              promotion_action_line_items_attributes: PallasTrade::PromotionActionLineItem.json_api_permitted_attributes.concat(conditional_params),
              calculator_attributes: PallasTrade::Calculator.json_api_permitted_attributes.concat(conditional_params, calculator_params)
            }], promotion_rules_attributes: PallasTrade::PromotionRule.json_api_permitted_attributes.concat(conditional_params, rule_params) }]
          end

          def resource_serializer
            PallasTrade.api.platform_promotion_serializer
          end
        end
      end
    end
  end
end
