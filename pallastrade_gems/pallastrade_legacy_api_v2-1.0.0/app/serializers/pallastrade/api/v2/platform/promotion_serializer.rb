module PallasTrade
  module Api
    module V2
      module Platform
        class PromotionSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :promotion_category, serializer: PallasTrade.api.platform_promotion_category_serializer

          has_many :promotion_rules, serializer: PallasTrade.api.platform_promotion_rule_serializer
          has_many :promotion_actions, serializer: PallasTrade.api.platform_promotion_action_serializer
          has_many :stores, serializer: PallasTrade.api.platform_store_serializer
        end
      end
    end
  end
end
