# frozen_string_literal: true

module PallasTrade
  # 订单流程标准电商改造 P1（2026-08-30）：购物车行（pallastrade_cart_items 表）。
  # 与 LineItem（订单行快照，pallastrade_line_items）语义分离：
  # - CartItem：购物车会话内的商品行，含勾选（selected）标记，价格实时读取 variant
  # - LineItem：提交订单时的商品快照（价格/税锁定），归属 Order
  # 提交订单（Carts::Submit）时 selected 的 CartItem → Order.line_items。
  class CartItem < PallasTrade.base_class
    has_prefix_id :ci

    include PallasTrade::Metadata

    belongs_to :cart, class_name: 'PallasTrade::Cart', inverse_of: :cart_items, touch: true
    belongs_to :variant, -> { with_deleted }, class_name: 'PallasTrade::Variant'

    has_one :product, -> { with_deleted }, class_name: 'PallasTrade::Product', through: :variant

    validates :cart, :variant, presence: true
    validates :quantity, numericality: { greater_than: 0, only_integer: true }
    validates :variant_id, uniqueness: { scope: :cart_id }

    scope :selected, -> { where(selected: true) }

    extend PallasTrade::DisplayMoney
    money_methods :unit_price, :amount

    delegate :sku, :options_text, :slug, :product_id, to: :variant
    delegate :name, :description, to: :product

    # 实时价格（BigDecimal）——Cart 不锁价，提交订单时由 LineItem 锁定。
    # @return [BigDecimal, nil] variant 在 cart 币种下无价格时返回 nil
    def unit_price
      variant.amount_in(cart.currency)
    end

    # 行金额 = 单价 × 数量。
    # @return [BigDecimal] 无价格时返回 0（序列化时以 hide_prices 控制泄露）
    def amount
      price = unit_price
      price.nil? ? 0 : price * quantity
    end

    def total
      amount
    end

    def thumbnail
      variant.primary_media || product.primary_media
    end
  end
end
