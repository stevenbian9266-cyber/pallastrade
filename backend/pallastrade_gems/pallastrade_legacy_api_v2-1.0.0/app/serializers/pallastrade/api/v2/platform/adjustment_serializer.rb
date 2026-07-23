module PallasTrade
  module Api
    module V2
      module Platform
        class AdjustmentSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :order, serializer: PallasTrade.api.platform_order_serializer
          belongs_to :adjustable, polymorphic: true
          belongs_to :source, polymorphic: {
            PallasTrade::Promotion::Actions::FreeShipping => PallasTrade.api.platform_promotion_action_serializer,
            PallasTrade::Promotion::Actions::CreateAdjustment => PallasTrade.api.platform_promotion_action_serializer,
            PallasTrade::Promotion::Actions::CreateItemAdjustments => PallasTrade.api.platform_promotion_action_serializer,
            PallasTrade::Promotion::Actions::CreateLineItems => PallasTrade.api.platform_promotion_action_serializer
          }
        end
      end
    end
  end
end
