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
                 items: 'Array<CartItem>',
                 gift_card: { nullable: true },
                 store_credit: { nullable: true }

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

        # 下单链路统一化（PRD-20260830-checkout）：统一下单页购物车模式需要可选支付方式。
        # 与 Order serializer 一致：store.payment_methods.active.available_on_front_end。
        many :payment_methods, resource: proc { PallasTrade.api.payment_method_serializer }

        # PRD-20260914-checkout-cart-gift-cards-canonical FR-005：车阶段的礼品卡**意图**。
        # 金额在提交生成 Order 时由 `apply_gift_card` 落地（车阶段零资金副作用），
        # 故此处只暴露 code + 余额展示，供 UI 展示「已应用/可移除」。
        attribute :gift_card do |cart|
          code = (cart.private_metadata || {})[PallasTrade::Carts::ApplyGiftCard::METADATA_KEY]
          next if code.blank?

          gift_card = cart.store.gift_cards.find_by(code: code)
          next if gift_card.nil?

          { code: gift_card.code, display_amount_remaining: gift_card.display_amount_remaining }
        end

        # PRD-20260914-checkout-cart-store-credits-canonical FR-006：店铺余额意图
        # （车阶段零资金副作用；金额在提交生成 Order 时由 Checkout::AddStoreCredit 落地）。
        attribute :store_credit do |cart|
          amount = PallasTrade::Carts::ApplyStoreCredit.requested_amount(cart)
          next if amount.nil?

          { amount: amount.to_s('F'), display_amount: PallasTrade::Money.new(amount, currency: cart.currency).to_s }
        end
      end
    end
  end
end
