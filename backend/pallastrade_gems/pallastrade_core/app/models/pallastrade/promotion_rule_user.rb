module PallasTrade
  class PromotionRuleUser < PallasTrade.base_class
    belongs_to :promotion_rule, class_name: 'PallasTrade::PromotionRule'
    belongs_to :user, class_name: "::#{PallasTrade.user_class}"

    validates :user, :promotion_rule, presence: true
    validates :user_id, uniqueness: { scope: :promotion_rule_id }, allow_nil: true
  end
end
