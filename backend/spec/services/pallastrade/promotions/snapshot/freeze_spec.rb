# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot AC-002 AC-003 AC-005
# 冻结服务：成交订单写快照（金额取 batch2 统一投影）、幂等、未成交不写、
# 投影冻结后读快照（历史不被当前定义漂移）。
RSpec.describe PallasTrade::Promotions::Snapshot::Freeze do
  let!(:store) { create(:store, code: 'promo_snapshot_freeze_store') }

  def build_order(state: nil)
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100,
                                           shipment_cost: 5)
    order.update_columns(state: state, status: state == 'pending' ? 'placed' : nil) if state
    order.reload
  end

  def coupon_promotion(code: 'FREEZE10', amount: 10, name: 'Freeze Promo')
    create(:promotion_with_order_adjustment, store: store, code: code, name: name,
                                             weighted_order_adjustment_amount: amount)
  end

  def apply_coupon(order, code)
    order.coupon_code = code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.reload
  end

  def complete!(order)
    order.update_columns(completed_at: Time.current, state: 'complete')
    order.reload
  end

  describe '成交订单冻结（AC-002）' do
    it 'writes the snapshot with projection amounts and a stable digest' do
      promotion = coupon_promotion
      order = complete!(apply_coupon(build_order, promotion.code))

      frozen = described_class.call(order)

      expect(frozen.size).to eq(1)
      row = order.order_promotions.reload.find_by(promotion_id: promotion.id)
      expect(row).to be_frozen
      expect(row.name).to eq('Freeze Promo')
      expect(row.code).to eq('freeze10')
      expect(row.kind).to eq('coupon_code')
      expect(row.currency).to eq(order.currency)
      expect(row.definition_digest).to match(/\A[0-9a-f]{64}\z/)
      expect(row.total_amount.to_d).to eq(row.item_amount + row.order_amount + row.shipping_amount)

      line = PallasTrade::Promotions::Projection::DiscountProjection.for(order: order.reload).first
      expect(row.total_amount.to_d).to eq(line.amount)
    end

    it 'records the order-level tier amount in order_amount' do
      promotion = coupon_promotion
      order = complete!(apply_coupon(build_order, promotion.code))

      described_class.call(order)

      row = order.order_promotions.reload.find_by(promotion_id: promotion.id)
      expect(row.order_amount.to_d).to eq(-10.to_d)
      expect(row.item_amount.to_d).to eq(0.to_d)
      expect(row.shipping_amount.to_d).to eq(0.to_d)
    end

    it 'is idempotent and never rewrites an already frozen snapshot（AC-002 / R2）' do
      promotion = coupon_promotion
      order = complete!(apply_coupon(build_order, promotion.code))
      described_class.call(order)
      before = order.order_promotions.reload.find_by(promotion_id: promotion.id).attributes

      promotion.update!(name: 'Renamed After Freeze')
      expect(described_class.call(order)).to eq([])

      after = order.order_promotions.reload.find_by(promotion_id: promotion.id).attributes
      expect(after).to eq(before)
    end

    it 'freezes a promotion whose eligible adjustment nets to zero（R8）' do
      promotion = coupon_promotion(code: 'ZEROFREEZE', amount: 10)
      order = complete!(apply_coupon(build_order, promotion.code))
      order.all_adjustments.promotion.where(source_id: promotion.actions.select(:id)).update_all(amount: 0)

      expect(described_class.call(order).size).to eq(1)
      row = order.order_promotions.reload.find_by(promotion_id: promotion.id)
      expect(row).to be_frozen
      expect(row.total_amount.to_d).to eq(0.to_d)
    end

    it 'leaves rows outside the projection untouched（R8）' do
      promotion = coupon_promotion(code: 'NOTAPPLIED')
      order = complete!(build_order)
      stale = PallasTrade::OrderPromotion.create!(order: order, promotion: promotion)

      expect(described_class.call(order)).to eq([])
      expect(stale.reload).not_to be_frozen
    end
  end

  describe '未成交订单不冻结（AC-003 / R1）' do
    it 'skips a cart order' do
      promotion = coupon_promotion(code: 'CARTFREEZE')
      order = apply_coupon(build_order, promotion.code)

      expect(described_class.call(order)).to eq([])
      expect(order.order_promotions.reload.find_by(promotion_id: promotion.id)&.frozen_at).to be_nil
    end

    it 'skips an unpaid pending order' do
      promotion = coupon_promotion(code: 'PENDINGFREEZE')
      order = apply_coupon(build_order(state: 'pending'), promotion.code)

      expect(described_class.call(order)).to eq([])
      expect(order.order_promotions.reload.find_by(promotion_id: promotion.id)&.frozen_at).to be_nil
    end

    it 'freezes on request when the caller already has a money-confirmed signal（force）' do
      promotion = coupon_promotion(code: 'FORCEDFREEZE')
      order = apply_coupon(build_order, promotion.code)

      expect(described_class.call(order, force: true).size).to eq(1)
      expect(order.order_promotions.reload.find_by(promotion_id: promotion.id)).to be_frozen
    end
  end

  describe '投影读快照（AC-005）' do
    it 'keeps the frozen name and code after the promotion changes' do
      promotion = coupon_promotion(code: 'DRIFTOLD')
      order = complete!(apply_coupon(build_order, promotion.code))
      described_class.call(order)

      promotion.update!(name: 'Drift New', code: 'DRIFTNEW')

      line = PallasTrade::Promotions::Projection::DiscountProjection.for(order: order.reload).first
      expect(line.name).to eq('Freeze Promo')
      expect(line.code).to eq('driftold')
      expect(order.reload.promo_code).to eq('driftold')
    end

    it 'still reads live definitions for an unfrozen cart' do
      promotion = coupon_promotion(code: 'LIVEOLD')
      order = apply_coupon(build_order, promotion.code)

      promotion.update!(name: 'Live New')

      line = PallasTrade::Promotions::Projection::DiscountProjection.for(order: order.reload).first
      expect(line.name).to eq('Live New')
    end
  end
end
