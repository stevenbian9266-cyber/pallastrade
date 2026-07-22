module PallasTrade
  module Api
    module V2
      module Platform
        class PromotionCategoriesController < ResourceController
          private

          def model_class
            PallasTrade::PromotionCategory
          end

          def scope_includes
            [:promotions]
          end

          def resource_serializer
            PallasTrade.api.platform_promotion_category_serializer
          end
        end
      end
    end
  end
end
