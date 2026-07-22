module PallasTrade
  module Api
    module V2
      module Platform
        class PromotionRulesController < ResourceController
          include ::PallasTrade::Api::V2::Platform::PromotionRuleParams

          private

          def model_class
            PallasTrade::PromotionRule
          end

          def scope_includes
            [:promotion]
          end

          def pallastrade_permitted_attributes
            super + rule_params
          end

          def resource_serializer
            PallasTrade.api.platform_promotion_rule_serializer
          end
        end
      end
    end
  end
end
