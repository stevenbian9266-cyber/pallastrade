# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot AC-004
# 状态机冻结点：legacy `complete` 与标准流程 `paid` 均写成交快照，且幂等。
RSpec.describe 'Order checkout snapshot freeze hooks' do
  let!(:store) { create(:store, code: 'promo_snapshot_hook_store') }

  def build_promotion(code: 'HOOK10')
    create(:promotion_with_order_adjustment, store: store, code: code, name: 'Hook Promo',
                                             weighted_order_adjustment_amount: 10)
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

  it 'freezes snapshots through the legacy complete transition（AC-004）' do
    promotion = build_promotion
    order = apply_coupon(build_order, promotion.code)
    move_to_confirm!(order)

    order.next!
    order.reload

    expect(order.state).to eq('complete')
    row = order.order_promotions.find_by(promotion_id: promotion.id)
    expect(row).to be_frozen
    expect(row.name).to eq('Hook Promo')
    expect(row.total_amount.to_d).to eq(-10.to_d)
  end

  it 'freezes snapshots through the standard-flow pay transition（AC-004）' do
    promotion = build_promotion(code: 'HOOKPAY')
    order = apply_coupon(build_order, promotion.code)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current)

    order.pay!
    order.reload

    expect(order.state).to eq('paid')
    row = order.order_promotions.find_by(promotion_id: promotion.id)
    expect(row).to be_frozen
    expect(row.code).to eq('hookpay')
  end

  it 'does not duplicate rows when both hooks run（AC-004 / R9）' do
    promotion = build_promotion(code: 'HOOKTWICE')
    order = apply_coupon(build_order, promotion.code)
    order.update_columns(state: 'paid', completed_at: Time.current)

    order.freeze_promotion_snapshots
    order.freeze_promotion_snapshots

    expect(order.order_promotions.reload.count).to eq(1)
    expect(order.order_promotions.where.not(frozen_at: nil).count).to eq(1)
  end
end
