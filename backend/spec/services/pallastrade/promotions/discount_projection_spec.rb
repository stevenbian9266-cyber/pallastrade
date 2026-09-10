# frozen_string_literal: true

require 'rails_helper'

# PRD-20260909-promotions-promo-batch2-discount-projection-unified AC-001 AC-002 AC-003 AC-004 AC-012
RSpec.describe PallasTrade::Promotions::Projection::DiscountProjection do
  let!(:store) { create(:store, code: 'promo_projection_store') }

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

  describe 'line contract（AC-001）' do
    it 'exposes the canonical fields for a coupon discount' do
      order = build_order(item_price: 100)
      create(:promotion_with_order_adjustment, store: store, code: 'SAVE20', weighted_order_adjustment_amount: 20)
      apply_coupon(order, 'SAVE20')

      line = described_class.for(order: order).first
      expect(line).not_to be_nil
      expect(line.id).to start_with('discount_')
      expect(line.promotion_id).to start_with('promo_')
      expect(line.name).to eq('Promo')
      expect(line.kind).to eq('coupon_code')
      expect(line.code).to eq('save20')
      expect(line.removable?).to be true
      expect(line.amount.to_f).to eq(-20.0)
      expect(line.display_amount.to_s).to include('-')
      expect(line.breakdown.keys).to contain_exactly(:items, :order, :shipping)
    end

    it 'returns an empty array when nothing was applied' do
      order = build_order(item_price: 100)
      expect(described_class.for(order: order)).to eq([])
    end
  end

  describe 'eligible-only aggregation（AC-002）' do
    it 'counts only the winning competing promotion (legacy OrderPromotion#amount gap closed)' do
      order = build_order(item_price: 100)
      create(:promotion_with_order_adjustment, store: store, kind: :automatic, code: nil, weighted_order_adjustment_amount: 5)
      create(:promotion_with_order_adjustment, store: store, kind: :automatic, code: nil, weighted_order_adjustment_amount: 30)
      activate_automatic(order)

      lines = described_class.for(order: order)

      expect(lines.length).to eq(1)
      expect(lines.first.amount.to_f).to eq(-30.0)
      expect(lines.first.removable?).to be false
      expect(lines.sum { |l| l.amount.to_f }).to eq(order.discount_total.to_f)

      legacy_sum = order.order_promotions.sum { |op| op.amount.to_f }
      expect(legacy_sum).to eq(-35.0) # legacy projection kept, no longer used for display
    end
  end

  describe 'three tiers + invariants（AC-003）' do
    it 'sums order + item + shipping tiers and matches discount_total / breakdown' do
      order = build_order(item_price: 100, shipment_cost: 10)
      create(:promotion_with_order_adjustment, store: store, code: 'SAVE20', weighted_order_adjustment_amount: 20)
      create(:promotion_with_item_adjustment, store: store, kind: :automatic, code: nil, adjustment_rate: 5)
      create(:free_shipping_promotion, store: store, kind: :automatic, code: nil)
      apply_coupon(order, 'SAVE20')
      activate_automatic(order)

      lines = described_class.for(order: order)
      total = lines.sum { |l| l.amount.to_f }

      expect(total).to eq(-35.0)
      expect(total).to eq(order.discount_total.to_f)
      lines.each do |line|
        expect(line.amount.to_f).to eq((line.item_amount + line.order_amount + line.shipping_amount).to_f)
      end
      expect(lines.find { |l| l.shipping_amount.to_f.negative? }.amount.to_f).to eq(-10.0)
    end
  end

  describe 'multi-code + removable flags（AC-004）' do
    it 'resolves the redeemed code for multi-code promos and marks coupon lines removable' do
      order = build_order(item_price: 100)
      promo = create(:promotion, store: store, kind: :coupon_code, multi_codes: true, code: nil, number_of_codes: 2)
      create(:promotion_action_create_adjustment, promotion: promo)
      promo.coupon_codes.create!(code: 'multi1')

      apply_coupon(order, 'multi1')

      line = described_class.for(order: order).first
      expect(line.code).to eq('multi1')
      expect(line.removable?).to be true
    end
  end

  describe 'read-only projection（AC-012）' do
    it 'never writes to promotions, actions, adjustments or order promotions' do
      order = build_order(item_price: 100)
      create(:promotion_with_order_adjustment, store: store, code: 'SAVE20', weighted_order_adjustment_amount: 20)
      apply_coupon(order, 'SAVE20')

      counts = lambda do
        [PallasTrade::Promotion, PallasTrade::PromotionAction, PallasTrade::Adjustment, PallasTrade::OrderPromotion].map(&:count)
      end

      before = counts.call
      described_class.for(order: order).to_a
      expect(counts.call).to eq(before)
    end
  end
end
