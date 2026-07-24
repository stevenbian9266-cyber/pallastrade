module PallasTrade
  class PromotionCategory < PallasTrade.base_class
    has_prefix_id :procat

    validates :name, presence: true
    has_many :promotions
  end
end
