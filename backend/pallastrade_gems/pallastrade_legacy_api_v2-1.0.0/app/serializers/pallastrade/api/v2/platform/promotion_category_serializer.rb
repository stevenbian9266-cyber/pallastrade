module PallasTrade
  module Api
    module V2
      module Platform
        class PromotionCategorySerializer < BaseSerializer
          include ResourceSerializerConcern

          has_many :promotions, serializer: PallasTrade.api.platform_promotion_serializer
        end
      end
    end
  end
end
