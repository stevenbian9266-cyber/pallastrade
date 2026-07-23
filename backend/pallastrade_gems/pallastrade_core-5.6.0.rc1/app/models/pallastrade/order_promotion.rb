module PallasTrade
  class OrderPromotion < PallasTrade.base_class
    has_prefix_id :discount

    belongs_to :order, class_name: 'PallasTrade::Order'
    belongs_to :promotion, class_name: 'PallasTrade::Promotion'

    delegate :name, :description, :code, :public_metadata, to: :promotion
    delegate :currency, to: :order

    validates :order, :promotion, presence: true
    validates :order, uniqueness: { scope: :promotion }

    extend PallasTrade::DisplayMoney
    money_methods :amount

    def amount
      order.all_adjustments.promotion.where(source: promotion.actions).sum(:amount)
    end
  end
end
