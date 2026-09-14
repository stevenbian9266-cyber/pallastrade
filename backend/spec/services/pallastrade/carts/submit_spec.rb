# frozen_string_literal: true

require 'spec_helper'

# PRD-20260829-checkout-订单流程标准电商改造 AC-002/AC-003（提交订单 → Order + Cart converted）
RSpec.describe PallasTrade::Carts::Submit, type: :service do
  let(:store) { @default_store }
  let(:product) { create(:product_in_stock, store: store) }
  let(:variant) { product.master }
  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en') }

  before do
    # 保证变体有 USD 价格 + 可用配送方式（履约管线 estimate_rates 需要）
    variant.set_price('USD', 19.99) unless variant.amount_in('USD')
    shipping_category = create(:shipping_category)
    product.update!(shipping_category_id: shipping_category.id)
    # zone 覆盖 US（address 默认国家）→ 生成运费
    zone = create(:zone)
    us = PallasTrade::Country.find_by(iso: 'US') || create(:country, iso: 'US', name: 'United States')
    zone.members << PallasTrade::ZoneMember.create(zoneable: us)
    create(:shipping_method, zones: [zone], shipping_categories: [shipping_category])
    # 收件地址（运费估算依赖 ship_address 有效）+ 游客邮箱（Order 必填校验）
    cart.update!(shipping_address: create(:address, user: nil), email: 'buyer@example.com')
  end

  def add_item(quantity: 2, selected: true)
    PallasTrade::Carts::UpsertItems.call(cart: cart, items: [{ variant_id: variant.prefixed_id, quantity: quantity, selected: selected }])
  end

  describe '#call' do
    it 'creates a pending standard-flow order and converts the cart' do
      add_item

      result = described_class.call(cart: cart)

      expect(result).to be_success
      order = result.value
      expect(order).to be_a(PallasTrade::Order)
      expect(order.state).to eq('pending')
      expect(order.status).to eq('placed')
      expect(order.submitted_at).to be_present
      expect(order.cart_id).to eq(cart.id)
      expect(order.email).to eq(cart.email)
      expect(order.currency).to eq('USD')

      expect(order.line_items.count).to eq(1)
      expect(order.line_items.first.variant_id).to eq(variant.id)
      expect(order.line_items.first.quantity).to eq(2)
      # 快照金额：行单价 × 数量
      expect(order.item_total).to eq(19.99 * 2)

      cart.reload
      expect(cart).to be_converted
      expect(cart.converted_at).to be_present
    end

    # PRD-20260914-checkout-cart-gift-cards-canonical AC-004：
    # 购物车上的礼品卡码在提交时兑现（车阶段零资金副作用 → 订单侧建 store-credit payment）。
    # 金额必须以**最终**订单 total 为上限（dev E2E 发现：在 update_with_updater! 之前兑现
    # 会读到 total=0 → store credit 金额 0 → 校验报「Amount must be greater than 0」）。
    it 'redeems the cart gift card against the final order total' do
      gift_card = create(:gift_card, store: store, amount: 10.00)
      cart.update!(private_metadata: { 'gift_card_code' => gift_card.code.downcase })
      add_item

      result = described_class.call(cart: cart)

      expect(result).to be_success
      order = result.value
      expect(order.gift_card_id).to eq(gift_card.id)
      expect(order.total).to be > 0
      expect(order.gift_card_total).to eq([BigDecimal('10.00'), order.total].min)
      expect(order.payments.store_credits.sum(:amount)).to eq(order.gift_card_total)
      expect(order.amount_due).to eq(order.total - order.gift_card_total)
      expect(gift_card.reload.amount_used).to eq(order.gift_card_total)
      expect(PallasTrade::Order.where(cart_id: cart.id).count).to eq(1)
    end

    # AC-004 边界：零额订单（全额折扣/免费商品）无款可付 → 不创建 0 额 store credit，
    # 也不占用礼品卡余额，提交本身照常成功。
    it 'leaves the gift card untouched when there is nothing to pay' do
      variant.set_price('USD', 0)
      # 免运费（FlatRate 置 0）+ 免费商品 → 订单 total 0（无款可付）
      PallasTrade::ShippingMethod.find_each { |method| method.calculator.update!(preferred_amount: 0) }
      add_item
      gift_card = create(:gift_card, store: store, amount: 10.00)
      cart.update!(private_metadata: { 'gift_card_code' => gift_card.code.downcase })

      result = described_class.call(cart: cart)

      expect(result).to be_success
      order = result.value
      expect(order.total).to eq(0)
      expect(order.payments.store_credits).to be_empty
      expect(gift_card.reload.amount_used).to eq(0)
    end

    # AC-004：提交时礼品卡不可用 → 提交失败且**不落单**（绝不静默按原价下单）
    it 'fails the submission and creates no order when the stored gift card is no longer valid' do
      cart.update!(private_metadata: { 'gift_card_code' => 'GONE' })
      add_item

      result = nil
      expect do
        result = described_class.call(cart: cart)
      end.not_to change { PallasTrade::Order.where(cart_id: cart.id).count }

      expect(result).not_to be_success
      expect(result.error.to_s).to include('gift_card_not_found')
      expect(cart.reload).not_to be_converted
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-005：
    # 购物车上的店铺余额意图在提交时兑现（权威 Checkout::AddStoreCredit；金额 = min(意图, 最终 outstanding)）。
    it 'redeems the cart store credit against the final order total' do
      buyer = create(:user)
      cart.update!(user: buyer, email: buyer.email)
      create(:store_credit, store: store, user: buyer, amount: 30.0, currency: 'USD')
      cart.update!(private_metadata: { 'store_credit_amount' => '20' })
      add_item

      result = described_class.call(cart: cart)

      expect(result).to be_success
      order = result.value
      applied = order.payments.store_credits.sum(:amount)
      expect(applied).to eq([BigDecimal('20'), order.total].min)
      expect(order.amount_due).to eq(order.total - applied)
      expect(PallasTrade::Order.where(cart_id: cart.id).count).to eq(1)
    end

    # 修复（dev 实测缺陷）：店铺里已存在但被**停用**的 store-credit 支付方式 →
    # `Checkout::AddStoreCredit` 的 `available` 作用域取不到 → raise。兑现路径必须自愈（激活并落库）。
    # 断言只针对**结果**（店铺恢复出可用支付方式）——CI 里店铺可能已有别的支付方式记录，
    # 断言"spec 造的那条被激活"会过窄（Backend CI 实测：兑现成功但该断言失败）。
    it 'activates an existing but disabled store credit payment method before redeeming' do
      buyer = create(:user)
      cart.update!(user: buyer, email: buyer.email)
      create(:store_credit, store: store, user: buyer, amount: 30.0, currency: 'USD')
      # 先让本店 store-credit 支付方式全部停用 → 确定性地覆盖「无可用 → 自愈」路径
      PallasTrade::PaymentMethod::StoreCredit.where(store: store).update_all(active: false)
      create(:store_credit_payment_method, store: store, active: false)
      cart.update!(private_metadata: { 'store_credit_amount' => '20' })
      add_item

      result = described_class.call(cart: cart)

      expect(result).to be_success
      expect(result.value.payments.store_credits.sum(:amount)).to eq(BigDecimal('20'))
      expect(PallasTrade::PaymentMethod::StoreCredit.available.where(store: store)).to be_present
    end

    # AC-005（异常路径）：权威服务 raise（支付方式不可用等）→ 收敛为「提交失败、不落单」，不是 500。
    it 'turns an authoritative service failure into an order-less submission failure' do
      buyer = create(:user)
      cart.update!(user: buyer, email: buyer.email)
      create(:store_credit, store: store, user: buyer, amount: 30.0, currency: 'USD')
      cart.update!(private_metadata: { 'store_credit_amount' => '20' })
      add_item
      failing_service = instance_double(PallasTrade::Checkout::AddStoreCredit)
      allow(failing_service).to receive(:call).and_raise('boom')
      allow(PallasTrade).to receive(:checkout_add_store_credit_service).and_return(failing_service)

      result = nil
      expect do
        result = described_class.call(cart: cart)
      end.not_to change { PallasTrade::Order.where(cart_id: cart.id).count }

      expect(result).not_to be_success
      expect(cart.reload).not_to be_converted
    end

    # AC-005：提交时余额不可用 → 提交失败且不落单
    it 'fails the submission and creates no order when the store credit is gone' do
      buyer = create(:user)
      cart.update!(user: buyer, email: buyer.email)
      cart.update!(private_metadata: { 'store_credit_amount' => '20' })
      add_item

      result = nil
      expect do
        result = described_class.call(cart: cart)
      end.not_to change { PallasTrade::Order.where(cart_id: cart.id).count }

      expect(result).not_to be_success
      expect(cart.reload).not_to be_converted
    end

    # PRD-20260914-checkout-cart-discount-codes-canonical AC-004：
    # 购物车上的优惠码在提交时兑现（金额生效，走权威 PromotionHandler::Coupon）。
    it 'applies the cart discount code to the submitted order' do
      create(:promotion_with_order_adjustment, store: store, code: 'SAVE10',
                                               weighted_order_adjustment_amount: 10)
      cart.update!(private_metadata: { 'discount_code' => 'save10' })
      add_item

      result = described_class.call(cart: cart)

      expect(result).to be_success
      order = result.value
      expect(order.coupon_code).to eq('save10')
      # 既有约定：折扣合计为负数（order_adjustments 为负数）
      expect(order.discount_total).to be < 0
      expect(PallasTrade::Order.where(cart_id: cart.id).count).to eq(1)
    end

    # PRD-20260914-checkout-cart-discount-codes-canonical AC-005：
    # 码不可用 → 提交失败且**不落单**（绝不静默按原价下单）
    it 'fails the submission and creates no order when the stored code is no longer valid' do
      cart.update!(private_metadata: { 'discount_code' => 'GONE' })
      add_item

      result = nil
      expect do
        result = described_class.call(cart: cart)
      end.not_to change { PallasTrade::Order.where(cart_id: cart.id).count }

      expect(result).not_to be_success
      # 失败原因来自权威 PromotionHandler（本地化用户消息），且购物车未被转换
      expect(result.error.to_s).to match(/coupon code/i)
      expect(cart.reload).not_to be_converted
    end

    # PRD-20260913-checkout-billing-mode AC-004：购物车无账单地址 → 回退复制配送地址
    it 'falls back to the shipping address when the cart has no billing address' do
      add_item

      result = described_class.call(cart: cart)

      expect(result).to be_success
      order = result.value
      shipping = cart.reload.shipping_address
      expect(order.bill_address).to be_present
      expect(order.bill_address.id).not_to eq(shipping.id) # 快照副本（dup）
      expect(order.bill_address.first_name).to eq(shipping.first_name)
      expect(order.bill_address.city).to eq(shipping.city)
      expect(order.bill_address.country_iso).to eq(shipping.country_iso)
    end

    # PRD-20260913-checkout-billing-mode AC-005：显式账单地址优先，不被配送地址覆盖
    it 'snapshots the explicit billing address when the cart has one' do
      add_item
      billing = create(:address, user: nil, first_name: 'Bill', city: 'Billingville')
      cart.update!(billing_address: billing)

      result = described_class.call(cart: cart)

      expect(result).to be_success
      order = result.value
      expect(order.bill_address).to be_present
      expect(order.bill_address.first_name).to eq('Bill')
      expect(order.bill_address.city).to eq('Billingville')
    end

    # PRD-20260830-checkout AC-003
    it 'only snapshots selected items and preserves unselected items in a successor cart' do
      add_item(quantity: 1, selected: true)
      unselected = create(:variant, product: create(:product, store: store))
      unselected.set_price('USD', 9.99)
      PallasTrade::Carts::UpsertItems.call(cart: cart, items: [{ variant_id: unselected.prefixed_id, quantity: 1, selected: false }])

      result = described_class.call(cart: cart)

      expect(result).to be_success
      expect(result.value.line_items.map(&:variant_id)).to eq([variant.id])
      successor = store.shopping_carts.active.find_by_prefix_id!(result.value.metadata[:successor_cart_id])
      expect(successor.cart_items.map(&:variant_id)).to eq([unselected.id])
      expect(successor.cart_items.first).not_to be_selected
      expect(cart.reload.cart_items.map(&:variant_id)).to eq([variant.id])
    end

    it 'rejects a cart with no selected items' do
      PallasTrade::Carts::UpsertItems.call(cart: cart, items: [{ variant_id: variant.prefixed_id, quantity: 1, selected: false }])

      result = described_class.call(cart: cart)

      expect(result).to be_failure
    end

    # PRD-20260830-checkout AC-007
    it 'replays the same order for an already-converted cart' do
      add_item
      first_order = described_class.call(cart: cart).value

      result = described_class.call(cart: cart)

      expect(result).to be_success
      expect(result.value).to eq(first_order)
      expect(cart.orders.count).to eq(1)
    end

    it 'snapshots the shipping address onto the order' do
      address = create(:address, user: nil)
      cart.update!(shipping_address: address, email: 'buyer@example.com')
      add_item

      result = described_class.call(cart: cart)

      expect(result).to be_success
      order = result.value
      expect(order.shipping_address).to be_present
      expect(order.shipping_address.address1).to eq(address.address1)
      # 快照（dup）——订单地址是独立新记录，非引用购物车地址
      expect(order.shipping_address.id).not_to eq(address.id)
    end

    it 'is idempotent under repeated webhook completion via Carts::Complete' do
      add_item
      order = described_class.call(cart: cart).value
      expect(order.state).to eq('pending')

      # 模拟支付完成（无真实支付时 Carts::Complete 标准分支报 no_payment_found）
      result = PallasTrade::Carts::Complete.call(cart: order)
      expect(result).to be_failure
      expect(result.error.to_s).to include('payment')
    end
  end
end
