module PallasTrade
  class PromotionRuleTaxon < PallasTrade.base_class
    belongs_to :promotion_rule, class_name: 'PallasTrade::PromotionRule'
    belongs_to :taxon, class_name: 'PallasTrade::Taxon'

    validates :promotion_rule, :taxon, presence: true
    validates :promotion_rule_id, uniqueness: { scope: :taxon_id }, allow_nil: true
  end
end
