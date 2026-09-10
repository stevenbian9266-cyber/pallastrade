# frozen_string_literal: true

require 'rails_helper'

# PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-001 AC-002 AC-003 AC-004 AC-005 AC-006 AC-007
# PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-008 AC-009 AC-010 AC-011 AC-012
# PRD-20260909-promotions-promo-batch2-discount-projection-unified AC-010
# PRD-20260910-promotions-promo-batch3a-redemption-ledger AC-011
# I1 discount_total==eligible sum; I2 recalc determinism; I3 remove idempotency;
# I4 best-per-adjustable; I5 no negative total; I6 OrderPromotion#amount gap.
RSpec.describe 'Promotion amount contracts', type: :model do
  let!(:store) { create(:store, code: 'promo_contract_store') }

  def build_order(item_price: 100, shipment_cost: nil)
    opts = { store: store, line_items_count: 1, line_items_price: item_price }
    opts[:shipment_cost] = shipment_cost if shipment_cost
    create(:order_with_line_items, opts)
  end

  def recalc(order)
    order.update_with_updater!
    order.reload
  end

  def activate_automatic(order)
    PallasTrade::PromotionHandler::Cart.new(order, nil).activate
    recalc(order)
  end

  def apply_coupon(order, code)
    order.coupon_code = code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    recalc(order)
  end

  def eligible_promo_sum(order)
    order.all_adjustments.promotion.eligible.sum(:amount).to_f
  end

  describe 'I1 discount_total == eligible promotion adjustments（AC-P0-2/AC-007）' do
    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P0-2/AC-007
    it 'order-level coupon discount' do
      order = build_order(item_price: 100, shipment_cost: 10)
      create(:promotion_with_order_adjustment, store: store, code: 'SAVE10', weighted_order_adjustment_amount: 20)

      apply_coupon(order, 'SAVE10')

      expect(order.discount_total.to_f).to eq(-20.0)
      expect(eligible_promo_sum(order)).to eq(order.discount_total.to_f)
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P0-2/AC-007
    it 'line-item discount（CreateItemAdjustments）' do
      order = build_order(item_price: 100)
      create(:promotion_with_item_adjustment, store: store, code: 'L10', adjustment_rate: 12)

      apply_coupon(order, 'L10')

      expect(order.discount_total.to_f).to eq(-12.0)
      expect(eligible_promo_sum(order)).to eq(order.discount_total.to_f)
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P0-2/AC-007
    it 'free shipping（shipment-tier adjustment）' do
      order = build_order(item_price: 50, shipment_cost: 15)
      create(:free_shipping_promotion, store: store, code: 'FS1')

      apply_coupon(order, 'FS1')

      expect(order.discount_total.to_f).to eq(-15.0)
      expect(eligible_promo_sum(order)).to eq(order.discount_total.to_f)
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P0-2/AC-007
    it 'order + line-item + shipment tiers coexist and all count toward discount_total' do
      order = build_order(item_price: 100, shipment_cost: 10)
      create(:promotion_with_order_adjustment, store: store, code: 'SAVE20', weighted_order_adjustment_amount: 20)
      create(:promotion_with_item_adjustment, store: store, kind: :automatic, code: nil, adjustment_rate: 5)
      create(:free_shipping_promotion, store: store, kind: :automatic, code: nil)

      apply_coupon(order, 'SAVE20')
      activate_automatic(order)

      expect(order.discount_total.to_f).to eq(-35.0) # -20 order - 5 item - 10 shipping
      expect(eligible_promo_sum(order)).to eq(order.discount_total.to_f)
    end
  end

  describe 'I2 recalculation is deterministic（AC-P0-3/AC-008）' do
    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P0-3/AC-008
    it 'repeated recalculation does not change totals' do
      order = build_order(item_price: 100, shipment_cost: 10)
      create(:promotion_with_order_adjustment, store: store, code: 'SAVE20', weighted_order_adjustment_amount: 20)
      create(:promotion_with_order_adjustment, store: store, kind: :automatic, code: nil, weighted_order_adjustment_amount: 5)

      apply_coupon(order, 'SAVE20')
      activate_automatic(order)

      snapshot = %i[item_total shipment_total adjustment_total discount_total tax_total total].map { |a| order.public_send(a).to_f }
      recalc(order)
      after = %i[item_total shipment_total adjustment_total discount_total tax_total total].map { |a| order.public_send(a).to_f }

      expect(after).to eq(snapshot)
    end
  end

  describe 'I3 coupon removal is idempotent（AC-P0-4/AC-009）' do
    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P0-4/AC-009
    it 'removing twice leaves the same state as removing once' do
      order = build_order(item_price: 100)
      create(:promotion_with_order_adjustment, store: store, code: 'R10', weighted_order_adjustment_amount: 10)

      apply_coupon(order, 'R10')
      expect(order.discount_total.to_f).to eq(-10.0)

      PallasTrade::PromotionHandler::Coupon.new(order).remove('R10')
      recalc(order)
      after_once = order.discount_total.to_f
      expect(after_once).to eq(0.0)

      # second remove is a no-op for state
      PallasTrade::PromotionHandler::Coupon.new(order).remove('R10')
      recalc(order)

      expect(order.reload.discount_total.to_f).to eq(after_once)
      expect(order.order_promotions.count).to eq(0)
    end
  end

  describe 'I4 best-per-adjustable（AC-P0-5/AC-010）' do
    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P0-5/AC-010
    it 'keeps exactly one eligible promo adjustment per adjustable, picking the largest discount' do
      order = build_order(item_price: 100)
      create(:promotion_with_order_adjustment, store: store, kind: :automatic, code: nil, weighted_order_adjustment_amount: 5)
      create(:promotion_with_order_adjustment, store: store, kind: :automatic, code: nil, weighted_order_adjustment_amount: 30)

      activate_automatic(order)

      eligible = order.all_adjustments.promotion.eligible.to_a
      expect(eligible.length).to eq(1)
      expect(eligible.first.amount.to_f).to eq(-30.0)
      expect(order.discount_total.to_f).to eq(-30.0)
    end
  end

  describe 'I5 discount never drives the order negative（AC-P0-6/AC-011）' do
    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P0-6/AC-011
    it 'caps an oversized order discount at the payable order total' do
      order = create(:order, store: store)
      create(:line_item, order: order, price: 100)
      order.line_items.reload
      recalc(order)

      create(:promotion_with_order_adjustment, store: store, code: 'BIG', weighted_order_adjustment_amount: 500)
      apply_coupon(order, 'BIG')

      expect(order.discount_total.to_f).to eq(-100.0)
      expect(order.total.to_f).to eq(0.0)
    end
  end

  describe 'I6 OrderPromotion#amount gap exposure（AC-P0-7/AC-012, :known_gap → Phase1/2 fix）' do
    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P0-7/AC-012
    it 'documents that an un-eligible competing adjustment is still summed by OrderPromotion#amount' do
      order = build_order(item_price: 100)
      create(:promotion_with_order_adjustment, store: store, kind: :automatic, code: nil, weighted_order_adjustment_amount: 5)
      create(:promotion_with_order_adjustment, store: store, kind: :automatic, code: nil, weighted_order_adjustment_amount: 30)

      activate_automatic(order)

      # both promotions activated and both order_promotions exist
      expect(order.order_promotions.count).to eq(2)
      op_sum = order.order_promotions.sum { |op| op.amount.to_f }
      expect(op_sum).to eq(-35.0) # unfiltered legacy projection
      expect(order.discount_total.to_f).to eq(-30.0) # authoritative eligible-only total
    end
  end
end
