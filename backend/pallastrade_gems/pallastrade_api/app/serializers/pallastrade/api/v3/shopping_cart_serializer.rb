module PallasTrade
  module Api
    module V3
      # 订单流程标准电商改造 P1（2026-08-30）：新购物车序列化器（pallastrade_carts）。
      # 与 legacy CartSerializer（Order 同表，含 checkout 进度）不同：
      # - 状态（active/converted/abandoned）而非 checkout step
      # - 商品行是 cart_items（含 selected 勾选），非 line_items
      # - 金额只含 item_total（运费/税费在提交订单后由 Order 权威计算）
      class ShoppingCartSerializer < BaseSerializer
        typelize id: :string, token: :string, status: :string,
                 email: [:string, nullable: true], customer_note: [:string, nullable: true],
                 currency: :string, locale: [:string, nullable: true],
                 item_count: :number, item_total: [:string, nullable: true],
                 display_item_total: [:string, nullable: true],
                 converted_at: [:string, nullable: true],
                 shipping_method_id: [:string, nullable: true],
                 billing_address: { nullable: true }, shipping_address: { nullable: true },
                 items: 'Array<CartItem>'

        attribute :id do |cart|
          cart.prefixed_id
        end

        attributes :token, :status, :email, :customer_note, :currency, :locale, :item_count

        attribute :converted_at do |cart|
          cart.converted_at&.iso8601
        end

        attribute :shipping_method_id do |cart|
          cart.shipping_method&.prefixed_id
        end

        # Nulled for gated (prices_hidden) guests so the cart can't leak the
        # prices that product/variant serializers already withhold.
        money_attributes :item_total, :display_item_total

        # 序列化框架按关联名取数（cart.cart_items），输出键为 items。
        many :cart_items, key: :items, resource: proc { PallasTrade.api.cart_item_serializer }
        one :billing_address, resource: proc { PallasTrade.api.address_serializer }
        one :shipping_address, resource: proc { PallasTrade.api.address_serializer }
      end
    end
  end
end
