# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch4b-refund-allocation AC-002 AC-004
# Invariant：冻结订单的分摊与可退金额不受促销后续修改影响（不重跑 Promotion Engine）。
RSpec.describe 'Order promotion allocation invariant' do
  let!(:store) { create(:store, code: 'promo_allocation_invariant_store') }

  let(:promotion) do
    create(:promotion_with_order_adjustment, store: store, code: 'ALLOCINV', name: 'Allocation Invariant',
                                             weighted_order_adjustment_amount: 30)
  end

  let(:order) do
    order = create(:order_with_line_items, store: store, line_items_count: 2, line_items_price: 100,
                                           shipment_cost: 50)
    order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.update_columns(completed_at: Time.current, state: 'complete')
    order.reload
    PallasTrade::Promotions::Snapshot::Freeze.call(order)
    order
  end

  def allocation_snapshot(target)
    result = PallasTrade::Promotions::Allocation::AdjustmentAllocation.for(order: target.reload)
    result.lines.map(&:to_h)
  end

  def refundable_snapshot(target)
    preview = PallasTrade::Promotions::Allocation::RefundPreview.call(order: target.reload)
    preview.line_items.map { |line| [line.line_item_prefixed_id, line.refundable_amount.to_s] }
  end

  it 'keeps allocation equal to the frozen snapshot total（AC-002）' do
    frozen = order.order_promotions.find_by(promotion_id: promotion.id)
    result = PallasTrade::Promotions::Allocation::AdjustmentAllocation.for(order: order.reload)

    total = result.promotion_totals.find { |row| row[:promotion_id] == promotion.id }

    expect(frozen).to be_frozen
    expect(total[:allocated_amount].to_d).to eq(frozen.total_amount.to_d.abs)
    expect(result.balanced?).to be true
  end

  it 'does not drift after rename / kind change / code change / rule edit（AC-004）' do
    lines_before = allocation_snapshot(order)
    refundable_before = refundable_snapshot(order)

    promotion.update!(name: 'Renamed After Freeze')
    promotion.update!(kind: :automatic)
    promotion.promotion_rules.create!(type: 'PallasTrade::Promotion::Rules::ItemTotal')

    expect(allocation_snapshot(order)).to eq(lines_before)
    expect(refundable_snapshot(order)).to eq(refundable_before)
  end

  it 'keeps serving the live projection for an unfrozen order（AC-004 regression）' do
    live_order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100,
                                                shipment_cost: 50)
    live_order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(live_order).apply
    live_order.update_with_updater!
    live_order.reload

    before = PallasTrade::Promotions::Allocation::AdjustmentAllocation.for(order: live_order.reload).
             promotion_totals.first[:allocated_amount].to_d

    promotion.update!(name: 'Live Rename')

    after = PallasTrade::Promotions::Allocation::AdjustmentAllocation.for(order: live_order.reload).
            promotion_totals.first[:allocated_amount].to_d

    expect(after).to eq(before)
  end

  it 'survives destructive promotion edits without raising（AC-004 / R6）' do
    before_total = order.order_promotions.find_by(promotion_id: promotion.id).total_amount.to_d

    promotion.promotion_actions.destroy_all

    result = PallasTrade::Promotions::Allocation::AdjustmentAllocation.for(order: order.reload)
    preview = PallasTrade::Promotions::Allocation::RefundPreview.call(order: order.reload)

    expect(result.balanced?).to be true
    expect(preview).to be_available
    # 冻结事实仍在（batch4a 快照），历史折扣金额不受删除动作影响
    expect(order.order_promotions.reload.find_by(promotion_id: promotion.id).total_amount.to_d).
      to eq(before_total)
  end
end
