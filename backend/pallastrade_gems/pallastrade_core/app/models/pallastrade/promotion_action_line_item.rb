module PallasTrade
  class PromotionActionLineItem < PallasTrade.base_class
    belongs_to :promotion_action, class_name: 'PallasTrade::Promotion::Actions::CreateLineItems'
    belongs_to :variant, class_name: 'PallasTrade::Variant'

    validates :promotion_action, :variant, :quantity, presence: true
    validates :quantity, numericality: { only_integer: true, message: PallasTrade.t('validation.must_be_int') }
  end
end
