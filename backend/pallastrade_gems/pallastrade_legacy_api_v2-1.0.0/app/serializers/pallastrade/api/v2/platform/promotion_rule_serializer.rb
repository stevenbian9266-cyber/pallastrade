module PallasTrade
  module Api
    module V2
      module Platform
        class PromotionRuleSerializer < BaseSerializer
          include ResourceSerializerConcern

          attribute :preferences do |promotion_rule|
            promotion_rule.preferences
          end

          belongs_to :promotion, serializer: PallasTrade.api.platform_promotion_serializer

          has_many :products, through: :product_promotion_rules, serializer: PallasTrade.api.platform_product_serializer, if: proc { |record| record.respond_to?(:product_promotion_rules) }
          has_many :users, through: :promotion_rule_users, serializer: PallasTrade.api.platform_user_serializer, if: proc { |record| record.respond_to?(:promotion_rule_users) }
          has_many :taxons, through: :promotion_rule_taxons, serializer: PallasTrade.api.platform_taxon_serializer, if: proc { |record| record.respond_to?(:promotion_rule_taxons) }
        end
      end
    end
  end
end
