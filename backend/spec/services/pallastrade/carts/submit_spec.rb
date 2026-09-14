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
