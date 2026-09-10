# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch4b-refund-allocation AC-001 AC-002 AC-003
# 只读分摊投影：三类 basis（line_item / order_prorata / shipment_prorata）+ 守恒 + 边界。
RSpec.describe PallasTrade::Promotions::Allocation::AdjustmentAllocation do
  let!(:store) { create(:store, code: 'promo_allocation_store') }

  def order_with_lines(prices: [100, 100], shipment_cost: 50)
    order = create(:order_with_line_items, store: store, line_items_count: 1,
                                           line_items_price: prices.first, shipment_cost: shipment_cost)
    prices.drop(1).each { |price| create(:line_item, order: order, price: price) }
    order.update_with_updater!
    order.reload
  end

  def order_level_promotion(code:, amount:, name: 'Order Allocation Promo')
    create(:promotion_with_order_adjustment, store: store, code: code, name: name,
                                             weighted_order_adjustment_amount: amount)
  end

  def item_level_promotion(code:, rate:)
    create(:promotion_with_item_adjustment, store: store, code: code, adjustment_rate: rate)
  end

  def apply_coupon(order, code)
    order.coupon_code = code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.reload
  end

  def lines_for(result, promotion)
    result.lines.select { |line| line.promotion_id == promotion.id }
  end

  describe '三类 basis（AC-001）' do
    it 'allocates line-level adjustments to their own line, order-level pro-rata, shipping pro-rata' do
      order = order_with_lines
      item_promo = item_level_promotion(code: 'ALLOCITEM', rate: 10)
      order_promo = order_level_promotion(code: 'ALLOCORDER', amount: 60)
      shipping_promo = create(:free_shipping_promotion, store: store, code: 'ALLOCSHIP')

      [item_promo, order_promo, shipping_promo].each { |promotion| apply_coupon(order, promotion.code) }
      result = described_class.for(order: order.reload)

      line_ids = order.line_items.order(:id).pluck(:id)

      item_lines = lines_for(result, item_promo)
      expect(item_lines.map(&:allocation_basis).uniq).to eq(['line_item'])
      expect(item_lines.map(&:line_item_id)).to contain_exactly(*line_ids)
      expect(item_lines.map(&:allocated_amount).map(&:to_f)).to eq([10.0, 10.0])

      order_lines = lines_for(result, order_promo)
      expect(order_lines.map(&:allocation_basis).uniq).to eq(['order_prorata'])
      expect(order_lines.sum(BigDecimal('0'), &:allocated_amount).to_d).to eq(60.to_d)
      expect(order_lines.map(&:allocated_amount).map(&:to_f)).to eq([30.0, 30.0])

      shipping_lines = lines_for(result, shipping_promo)
      expect(shipping_lines.map(&:allocation_basis).uniq).to eq(['shipment_prorata'])
      expect(shipping_lines.sum(BigDecimal('0'), &:allocated_amount).to_d).to eq(50.to_d)
      expect(shipping_lines.map(&:allocated_amount).map(&:to_f)).to eq([25.0, 25.0])

      expect(result.allocated_for_line_item(line_ids.first).to_d).to eq(65.to_d)
    end

    it 'prorates by pre-tax share when line prices differ' do
      order = order_with_lines(prices: [100, 300])
      order_promo = order_level_promotion(code: 'ALLOCSHARE', amount: 40)
      apply_coupon(order, order_promo.code)
      result = described_class.for(order: order.reload)

      # pre_tax: 100 / 300 → 1:3 分摊 40 = 10 / 30
      expect(lines_for(result, order_promo).map(&:allocated_amount).map(&:to_f)).to eq([10.0, 30.0])
    end

    it 'ignores non-promotion adjustments（R2）' do
      order = order_with_lines
      PallasTrade::Adjustment.create!(
        order: order, adjustable: order, source: nil, amount: -5, label: 'Manual credit', eligible: true
      )

      result = described_class.for(order: order.reload)

      expect(result.promotion_totals).to be_empty
      expect(result.balanced?).to be true
    end
  end

  describe '守恒与舍入（AC-002）' do
    it 'keeps Σ allocation == snapshot total for uneven shares' do
      order = order_with_lines(prices: [100, 100, 100])
      promo = order_level_promotion(code: 'ALLOCROUND', amount: 10)
      apply_coupon(order, promo.code)

      result = described_class.for(order: order.reload)
      allocated = lines_for(result, promo).map { |line| line.allocated_amount.to_f }.sort

      expect(allocated).to eq([3.33, 3.33, 3.34])
      expect(allocated.sum.round(2)).to eq(10.0)
      expect(result.balanced?).to be true
    end

    it 'is deterministic regardless of line order' do
      order = order_with_lines(prices: [100, 100, 100])
      promo = order_level_promotion(code: 'ALLOCSTABLE', amount: 10)
      apply_coupon(order, promo.code)

      first = described_class.for(order: order.reload).lines.map(&:to_h)
      second = described_class.for(order: order.reload).lines.map(&:to_h)

      expect(second).to eq(first)
    end

    it 'reports balanced for every promotion on a mixed basket' do
      order = order_with_lines(prices: [120, 80])
      item_promo = item_level_promotion(code: 'ALLOCMIXITEM', rate: 15)
      order_promo = order_level_promotion(code: 'ALLOCMIXORDER', amount: 33)
      apply_coupon(order, item_promo.code)
      apply_coupon(order, order_promo.code)

      result = described_class.for(order: order.reload)

      expect(result.promotion_totals.size).to eq(2)
      expect(result.balanced?).to be true
      result.promotion_totals.each do |total|
        expect(total[:allocated_amount].to_d).to eq(total[:original_amount].to_d)
      end
    end
  end

  describe '边界（AC-003）' do
    it 'returns an empty, balanced result without promotions' do
      order = order_with_lines

      result = described_class.for(order: order.reload)

      expect(result.lines).to be_empty
      expect(result.promotion_totals).to be_empty
      expect(result.balanced?).to be true
      expect(result.total_allocated.to_d).to eq(0.to_d)
    end

    it 'falls back to the largest line when pre-tax item total is zero（R3）' do
      order = order_with_lines(prices: [100, 300])
      promo = order_level_promotion(code: 'ALLOCZERO', amount: 20)
      apply_coupon(order, promo.code)
      order.line_items.each { |line_item| line_item.update_columns(pre_tax_amount: 0) }

      result = described_class.for(order: order.reload)
      allocated = lines_for(result, promo).map(&:allocated_amount).map(&:to_f)
      largest = order.line_items.max_by { |line_item| line_item.amount.to_d }

      expect(allocated).to eq([20.0])
      expect(lines_for(result, promo).first.line_item_id).to eq(largest.id)
      expect(result.balanced?).to be true
    end

    it 'returns an empty result for a nil order' do
      result = described_class.for(order: nil)

      expect(result.lines).to be_empty
      expect(result.balanced?).to be true
    end
  end
end
