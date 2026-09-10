# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch3a-redemption-ledger AC-004 AC-005 AC-006 AC-007 AC-010 AC-012
# 核销台账服务的端到端行为：apply 不消耗 / complete 核销 / cancel 释放 /
# usage_limit 读 ledger / 事件 / 全流程幂等。
RSpec.describe 'Promotion redemption ledger' do
  let!(:store) { create(:store, code: 'promo_redemption_flow_store') }

  def build_order(item_price: 100)
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: item_price)
  end

  def coupon_promotion(code: 'SAVE10', amount: 10, usage_limit: nil)
    create(:promotion_with_order_adjustment, store: store, code: code,
                                             weighted_order_adjustment_amount: amount,
                                             usage_limit: usage_limit)
  end

  def multi_code_promotion
    promo = create(:promotion, store: store, kind: :coupon_code, multi_codes: true, code: nil, number_of_codes: 1)
    create(:promotion_action_create_adjustment, promotion: promo)
    promo.reload
  end

  def apply_coupon(order, code)
    order.coupon_code = code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.reload
  end

  describe 'cart apply does not consume（AC-004 / G1）' do
    it 'keeps a multi-code unused and creates no redemption' do
      promo = multi_code_promotion
      code = promo.coupon_codes.first
      order = build_order

      apply_coupon(order, code.code)

      expect(code.reload.state).to eq('unused')
      expect(code.order_id).to eq(order.id) # 仅关联，供投影展示 code
      expect(order.promotion_redemptions.count).to eq(0)
    end
  end

  describe 'order completion commits the ledger（AC-005 / G3）' do
    it 'creates one committed redemption per promotion and consumes the code' do
      promo = multi_code_promotion
      code = promo.coupon_codes.first
      order = build_order
      apply_coupon(order, code.code)

      PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)

      redemptions = order.promotion_redemptions.reload
      expect(redemptions.committed.count).to eq(1)
      expect(redemptions.first.promotion_id).to eq(promo.id)
      expect(redemptions.first.coupon_code_id).to eq(code.id)
      expect(redemptions.first.amount.to_f).to be < 0
      expect(code.reload.state).to eq('used')
      expect(code.order_id).to eq(order.id)
    end

    it 'is idempotent when called twice（AC-012）' do
      promotion = coupon_promotion
      order = build_order
      apply_coupon(order, promotion.code)

      PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)
      PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)

      expect(order.promotion_redemptions.reload.count).to eq(1)
      expect(order.promotion_redemptions.committed.count).to eq(1)
    end
  end

  describe 'order cancellation releases（AC-006 / G4）' do
    it 'releases the redemption and returns the coupon code to unused' do
      promo = multi_code_promotion
      code = promo.coupon_codes.first
      order = build_order
      apply_coupon(order, code.code)
      PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)

      PallasTrade::Promotions::Redemption::ReleaseOrder.call(order)

      redemption = order.promotion_redemptions.reload.first
      expect(redemption).to be_redemption_released
      expect(redemption.release_reason).to eq('order_canceled')
      expect(code.reload.state).to eq('unused')
      expect(code.order_id).to be_nil
    end
  end

  describe 'usage_limit reads the ledger（AC-007 / G2）' do
    it 'blocks a second order once the limit is committed' do
      promotion = coupon_promotion(code: 'LIMITED', usage_limit: 1)
      first = build_order
      apply_coupon(first, promotion.code)
      PallasTrade::Promotions::Redemption::FinalizeOrder.call(first)
      expect(first.promotion_redemptions.committed.count).to eq(1)

      second = build_order
      second.coupon_code = promotion.code
      handler = PallasTrade::PromotionHandler::Coupon.new(second)
      handler.apply

      expect(handler.status_code).to eq(:coupon_code_max_usage)
      expect(second.promotion_redemptions.count).to eq(0)
    end

    it 'does not count the current order redemption against itself' do
      promotion = coupon_promotion(code: 'SELF', usage_limit: 1)
      order = build_order
      apply_coupon(order, promotion.code)
      PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)

      expect(promotion.reload.credits_count).to eq(1)
      expect(promotion.usage_limit_exceeded?(order)).to be false
    end
  end

  describe 'events（AC-010）' do
    it 'publishes committed and released events with order/promotion payload' do
      promotion = coupon_promotion
      order = build_order
      apply_coupon(order, promotion.code)
      redemption = PallasTrade::Promotions::Redemption::Reserve.call(order: order, promotion: promotion)

      expect(redemption).to receive(:publish_event).with(
        'promotion.redemption_committed',
        hash_including('order_id' => order.prefixed_id, 'promotion_id' => promotion.prefixed_id)
      ).and_call_original
      PallasTrade::Promotions::Redemption::Commit.call(redemption)

      expect(redemption).to receive(:publish_event).with(
        'promotion.redemption_released',
        hash_including('release_reason' => 'coupon_removed')
      ).and_call_original
      PallasTrade::Promotions::Redemption::Release.call(redemption, reason: 'coupon_removed')
    end
  end

  describe 'full flow（AC-012）' do
    it 'apply → remove → re-apply → complete keeps exactly one committed redemption' do
      promotion = coupon_promotion
      order = build_order

      apply_coupon(order, promotion.code)
      expect(order.promotion_redemptions.count).to eq(0)

      PallasTrade::PromotionHandler::Coupon.new(order).remove(promotion.code)
      expect(order.reload.promotion_redemptions.count).to eq(0)
      expect(order.promotions).not_to include(promotion)

      apply_coupon(order, promotion.code)
      PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)
      PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)

      expect(order.promotion_redemptions.reload.committed.count).to eq(1)
    end

    it 'does not raise when removing a multi-code coupon from a cart（AC-013）' do
      promo = multi_code_promotion
      code = promo.coupon_codes.first
      order = build_order
      apply_coupon(order, code.code)

      handler = PallasTrade::PromotionHandler::Coupon.new(order)
      expect { handler.remove(code.code) }.not_to raise_error
      expect(code.reload.state).to eq('unused')
      expect(code.order_id).to be_nil
    end
  end
end
