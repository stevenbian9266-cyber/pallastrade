# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch3b-redemption-hardening AC-005 AC-006
# 事件兜底：payment_confirmed → FinalizeOrder（幂等）；全额退款 → 释放名额。
RSpec.describe PallasTrade::Promotions::RedemptionSubscriber, type: :job do
  let!(:store) { create(:store, code: 'promo_subscriber_store') }
  let(:subscriber) { described_class.new }

  def event(name, payload)
    double(name: name, payload: payload)
  end

  def build_order
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
  end

  def coupon_promotion(code)
    create(:promotion_with_order_adjustment, store: store, code: code, weighted_order_adjustment_amount: 10)
  end

  def apply_coupon(order, code)
    order.coupon_code = code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.reload
  end

  it 'declares both subscriptions（AC-005）' do
    expect(described_class.subscription_patterns).
      to include('commerce_transaction.payment_confirmed', 'refund.succeeded')
  end

  describe 'commerce_transaction.payment_confirmed（AC-005）' do
    it 'finalizes order redemptions and stays idempotent' do
      promotion = coupon_promotion('SUB1')
      order = build_order
      apply_coupon(order, promotion.code)

      txn = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100)
      PallasTrade::TransactionOrder.create!(commerce_transaction: txn, order: order,
                                            amount_snapshot: order.total)

      payload = { 'id' => txn.prefixed_id }
      subscriber.call(event('commerce_transaction.payment_confirmed', payload))

      expect(order.promotion_redemptions.committed.count).to eq(1)

      subscriber.call(event('commerce_transaction.payment_confirmed', payload))
      expect(order.promotion_redemptions.committed.count).to eq(1)
    end

    it 'ignores unknown transactions' do
      expect { subscriber.call(event('commerce_transaction.payment_confirmed', { 'id' => 'txn_missing' })) }.
        not_to raise_error
    end
  end

  describe 'refund.succeeded（AC-006）' do
    def build_refunded_order(promotion_code, refund_amount:)
      order = build_order
      promotion = coupon_promotion(promotion_code)
      apply_coupon(order, promotion.code)
      PallasTrade::Promotions::Redemption::FinalizeOrder.call(order)
      total = order.total.to_f

      payment_method = create(:bogus_payment_method, store: store, active: true)
      payment = create(:payment, order: order, payment_method: payment_method, amount: total,
                                 state: 'completed', source: nil, skip_source_requirement: true)
      # payment_total 在 Payment 落库后回写（Payment 校验 amount <= order.total - payment_total）。
      order.update_columns(payment_total: total)
      refund = create(:refund, payment: payment, amount: refund_amount || total)

      [order, refund]
    end

    it 'releases the redemption on a full refund' do
      order, refund = build_refunded_order('SUB2', refund_amount: nil)
      redemption = order.promotion_redemptions.first
      expect(redemption).to be_redemption_committed

      subscriber.call(event('refund.succeeded', { 'id' => refund.prefixed_id }))

      redemption.reload
      expect(redemption).to be_redemption_released
      expect(redemption.release_reason).to eq('refunded')

      # 幂等：重复事件不产生副作用
      released_at = redemption.released_at
      subscriber.call(event('refund.succeeded', { 'id' => refund.prefixed_id }))
      expect(redemption.reload.released_at).to eq(released_at)
    end

    it 'keeps the redemption on a partial refund' do
      order, refund = build_refunded_order('SUB3', refund_amount: nil)
      refund.update_columns(amount: order.total.to_f / 2)

      subscriber.call(event('refund.succeeded', { 'id' => refund.prefixed_id }))

      expect(order.promotion_redemptions.first.reload).to be_redemption_committed
    end

    it 'ignores failed refunds' do
      order, refund = build_refunded_order('SUB4', refund_amount: nil)
      refund.update_columns(state: 'failed')

      subscriber.call(event('refund.succeeded', { 'id' => refund.prefixed_id }))

      expect(order.promotion_redemptions.first.reload).to be_redemption_committed
    end
  end
end
