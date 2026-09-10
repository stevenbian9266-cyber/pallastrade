# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch3b-redemption-hardening AC-001 AC-002
# 并发加固：usage_limit 竞争下先成交者胜出、后到者不写核销也不占码；
# released 行复用（唯一索引不允许同键二次插入）。
RSpec.describe 'Promotion redemption hardening' do
  let!(:store) { create(:store, code: 'promo_redemption_hardening_store') }

  def build_order
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
  end

  def coupon_promotion(code:, usage_limit: nil, amount: 10)
    create(:promotion_with_order_adjustment, store: store, code: code,
                                             weighted_order_adjustment_amount: amount,
                                             usage_limit: usage_limit)
  end

  def apply_coupon(order, code)
    order.coupon_code = code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.reload
  end

  describe 'usage-limit race（AC-001）' do
    it 'keeps the first committed redemption and skips the loser without raising' do
      promotion = coupon_promotion(code: 'RACE1', usage_limit: 1)
      winner = build_order
      loser = build_order
      apply_coupon(winner, promotion.code)
      apply_coupon(loser, promotion.code)

      PallasTrade::Promotions::Redemption::FinalizeOrder.call(winner)
      expect(winner.promotion_redemptions.committed.count).to eq(1)

      expect(loser).to receive(:publish_event).
        with('promotion.redemption_limit_overshoot', hash_including('order_id' => loser.prefixed_id)).
        and_call_original

      expect { PallasTrade::Promotions::Redemption::FinalizeOrder.call(loser) }.not_to raise_error

      expect(loser.promotion_redemptions.count).to eq(0)
      expect(promotion.reload.credits_count).to eq(1)
    end

    it 'finalizes both orders when the promotion has no usage limit' do
      promotion = coupon_promotion(code: 'NOLIMIT1')
      first = build_order
      second = build_order
      apply_coupon(first, promotion.code)
      apply_coupon(second, promotion.code)

      PallasTrade::Promotions::Redemption::FinalizeOrder.call(first)
      PallasTrade::Promotions::Redemption::FinalizeOrder.call(second)

      expect(first.promotion_redemptions.committed.count).to eq(1)
      expect(second.promotion_redemptions.committed.count).to eq(1)
    end
  end

  describe 'released row reuse（AC-002）' do
    it 'revives the released row instead of inserting a second one' do
      promotion = coupon_promotion(code: 'REUSE1')
      order = build_order
      apply_coupon(order, promotion.code)

      first = PallasTrade::Promotions::Redemption::Reserve.call(order: order, promotion: promotion)
      PallasTrade::Promotions::Redemption::Commit.call(first)
      PallasTrade::Promotions::Redemption::Release.call(first, reason: 'order_canceled')
      expect(first.reload).to be_redemption_released

      revived = PallasTrade::Promotions::Redemption::Reserve.call(order: order, promotion: promotion)

      expect(revived.id).to eq(first.id)
      expect(revived.reload).to be_redemption_reserved
      expect(revived.release_reason).to be_nil
      expect(order.promotion_redemptions.count).to eq(1)
    end

    it 'returns the active row unchanged when called twice' do
      promotion = coupon_promotion(code: 'REUSE2')
      order = build_order
      apply_coupon(order, promotion.code)

      first = PallasTrade::Promotions::Redemption::Reserve.call(order: order, promotion: promotion)
      second = PallasTrade::Promotions::Redemption::Reserve.call(order: order, promotion: promotion)

      expect(second.id).to eq(first.id)
      expect(second).to be_redemption_reserved
      expect(order.promotion_redemptions.count).to eq(1)
    end
  end
end
