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

    it 'only snapshots selected items' do
      add_item(quantity: 1, selected: true)
      unselected = create(:variant, product: create(:product, store: store))
      unselected.set_price('USD', 9.99)
      PallasTrade::Carts::UpsertItems.call(cart: cart, items: [{ variant_id: unselected.prefixed_id, quantity: 1, selected: false }])

      result = described_class.call(cart: cart)

      expect(result).to be_success
      expect(result.value.line_items.map(&:variant_id)).to eq([variant.id])
    end

    it 'rejects a cart with no selected items' do
      PallasTrade::Carts::UpsertItems.call(cart: cart, items: [{ variant_id: variant.prefixed_id, quantity: 1, selected: false }])

      result = described_class.call(cart: cart)

      expect(result).to be_failure
    end

    it 'rejects an already-converted cart' do
      add_item
      described_class.call(cart: cart)

      result = described_class.call(cart: cart)

      expect(result).to be_failure
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
