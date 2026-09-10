# frozen_string_literal: true

require 'rails_helper'

# PRD-20260909-promotions-promo-batch2-discount-projection-unified AC-005 AC-006 AC-007 AC-009 AC-011
# PRD-20260910-promotions-promo-batch3a-redemption-ledger AC-011
# AC-005/006/007: Cart / Order / AdminOrder / Checkout return the SAME canonical
# discount payload; AC-009: serialization no longer calls OrderPromotion#amount;
# AC-011: rendering cost does not grow linearly with promotions (no N+1 sum).
RSpec.describe 'Promotion discount projection parity', type: :model do
  let!(:store) { create(:store, code: 'promo_parity_store') }

  def build_order(item_price: 100, shipment_cost: nil)
    opts = { store: store, line_items_count: 1, line_items_price: item_price }
    opts[:shipment_cost] = shipment_cost if shipment_cost
    create(:order_with_line_items, opts)
  end

  def recalc(order)
    order.update_with_updater!
    order.reload
  end

  def apply_coupon(order, code)
    order.coupon_code = code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    recalc(order)
  end

  def with_promotions(order)
    create(:promotion_with_order_adjustment, store: store, code: 'SAVE20', weighted_order_adjustment_amount: 20)
    create(:promotion_with_item_adjustment, store: store, kind: :automatic, code: nil, adjustment_rate: 5)
    create(:free_shipping_promotion, store: store, kind: :automatic, code: nil)
    apply_coupon(order, 'SAVE20')
    PallasTrade::PromotionHandler::Cart.new(order, nil).activate
    recalc(order)
  end

  def json(serializer)
    JSON.parse(serializer.to_json)
  end

  def cart_discounts(order)
    json(PallasTrade.api.cart_serializer.new(order, params: { store: store }))['discounts']
  end

  def order_discounts(order)
    json(PallasTrade.api.order_serializer.new(order, params: { store: store }))['discounts']
  end

  def admin_discounts(order)
    json(PallasTrade.api.admin_order_serializer.new(order, params: { store: store, expand: ['discounts'] }))['discounts']
  end

  def checkout_discounts(order)
    view = PallasTrade::OrderCheckout::View.call(order: order)
    json(PallasTrade::Api::V3::Store::Checkout::CheckoutSerializer.new(view, params: { store: store }))['discounts']
  end

  def count_queries(&block)
    count = 0
    callback = lambda do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      count += 1 unless event.payload[:name].in?(%w[SCHEMA CACHE])
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    count
  end

  it 'Cart == Order == Admin(expand) == Checkout and SUM == discount_total（AC-005/006/007）' do
    order = with_promotions(build_order(item_price: 100, shipment_cost: 10))

    cart = cart_discounts(order)
    order_payload = order_discounts(order)
    checkout = checkout_discounts(order)
    admin = admin_discounts(order)

    expect(cart).to eq(order_payload)
    expect(cart).to eq(checkout)
    expect(cart).to eq(admin)

    expect(cart.sum { |d| d['amount'].to_d }).to eq(order.discount_total.to_d)
    cart.each do |d|
      breakdown_sum = d['breakdown'].values.sum(&:to_d)
      expect(d['amount'].to_d).to eq(breakdown_sum)
    end
    expect(cart.map { |d| d['name'] }).to include('Promo')
    expect(cart.any? { |d| d['removable'] }).to be true
  end

  it 'does not call the legacy OrderPromotion#amount during serialization（AC-009）' do
    order = with_promotions(build_order(item_price: 100, shipment_cost: 10))

    expect_any_instance_of(PallasTrade::OrderPromotion).not_to receive(:amount)

    cart_discounts(order)
    checkout_discounts(order)
  end

  it 'renders discounts with bounded queries regardless of promotion count（AC-011）' do
    one = build_order(item_price: 100)
    create(:promotion_with_order_adjustment, store: store, code: 'ONE', weighted_order_adjustment_amount: 10)
    apply_coupon(one, 'ONE')
    q1 = count_queries { cart_discounts(one) }

    three = with_promotions(build_order(item_price: 100, shipment_cost: 10))
    q3 = count_queries { cart_discounts(three) }

    expect(q3).to be <= q1 + 2
  end
end
