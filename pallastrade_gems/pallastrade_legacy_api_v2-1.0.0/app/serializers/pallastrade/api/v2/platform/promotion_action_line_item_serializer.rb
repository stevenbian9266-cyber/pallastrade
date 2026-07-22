module PallasTrade
  module Api
    module V2
      module Platform
        class PromotionActionLineItemSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :promotion_action, serializer: PallasTrade.api.platform_promotion_action_serializer
          belongs_to :variant, serializer: PallasTrade.api.platform_variant_serializer
        end
      end
    end
  end
end
