module PallasTrade
  module Api
    module V3
      # 订单流程标准电商改造 P1（2026-08-30）：购物车行序列化器（pallastrade_cart_items）。
      # 含 selected 勾选标记；价格实时读取 variant（未锁价——提交订单时由 LineItem 锁定）。
      class CartItemSerializer < BaseSerializer
        typelize id: :string, variant_id: :string, quantity: :number, selected: :boolean,
                 name: :string, slug: :string, options_text: :string, currency: :string,
                 unit_price: [:string, nullable: true], display_unit_price: [:string, nullable: true],
                 amount: [:string, nullable: true], display_amount: [:string, nullable: true],
                 thumbnail_url: [:string, nullable: true]

        attribute :id do |cart_item|
          cart_item.prefixed_id
        end

        attribute :variant_id do |cart_item|
          cart_item.variant&.prefixed_id
        end

        attribute :currency do |cart_item|
          cart_item.cart&.currency
        end

        attributes :quantity, :selected, :name, :slug, :options_text

        # Nulled for gated (prices_hidden) guests so the cart's items can't
        # leak the prices that product/variant serializers already withhold.
        money_attributes :unit_price, :display_unit_price, :amount, :display_amount

        # Thumbnail URL for the cart item (variant thumbnail or product thumbnail)
        attribute :thumbnail_url do |cart_item|
          image_url_for(cart_item.thumbnail)
        end
      end
    end
  end
end
