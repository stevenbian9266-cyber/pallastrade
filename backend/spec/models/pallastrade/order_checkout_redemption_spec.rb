# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch3a-redemption-ledger AC-009
# Order::Checkout 状态机挂接：complete → 核销；canceled → 释放。
RSpec.describe 'Order checkout redemption hooks' do
  let!(:store) { create(:store, code: 'promo_checkout_hook_store') }

  def build_promotion(code: 'CHECKOUT10', amount: 10)
    create(:promotion_with_order_adjustment, store: store, code: code, weighted_order_adjustment_amount: amount)
  end

  def build_order
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
  end

  def apply_coupon(order, code)
    order.coupon_code = code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.reload
  end

  def move_to_confirm!(order)
    order.update_columns(state: 'confirm')
    allow(order).to receive(:payment_required?).and_return(false)
  end

  it 'commits redemptions through the complete transition（AC-009）' do
    promotion = build_promotion
    order = build_order
    apply_coupon(order, promotion.code)
    move_to_confirm!(order)

    order.next!
    order.reload

    expect(order.state).to eq('complete')
    expect(order.promotion_redemptions.committed.count).to eq(1)
    expect(order.promotion_redemptions.committed.first.promotion_id).to eq(promotion.id)
  end

  it 'releases redemptions through the cancel transition（AC-009）' do
    promotion = build_promotion(code: 'CANCEL10')
    order = build_order
    apply_coupon(order, promotion.code)
    PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)

    order.update_columns(state: 'confirm')
    allow(order).to receive(:allow_cancel?).and_return(true)

    order.cancel!
    order.reload

    expect(order.state).to eq('canceled')
    redemption = order.promotion_redemptions.first
    expect(redemption).to be_redemption_released
    expect(redemption.release_reason).to eq('order_canceled')
  end
end
