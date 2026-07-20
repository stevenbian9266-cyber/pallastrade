module PallasTrade
  class ProductPromotionRule < PallasTrade.base_class
    belongs_to :product, class_name: 'PallasTrade::Product'
    belongs_to :promotion_rule, class_name: 'PallasTrade::PromotionRule'

    validates :product, :promotion_rule, presence: true
    validates :product_id, uniqueness: { scope: :promotion_rule_id }, allow_nil: true
  end
end
