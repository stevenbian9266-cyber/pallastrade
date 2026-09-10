# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch3b-redemption-hardening AC-003 AC-007 AC-008
# reserved 行的 TTL 出口：保守释放（有支付证据不释放）、幂等、统计日志。
RSpec.describe PallasTrade::Promotions::Redemption::ExpireSweeperJob, type: :job do
  let!(:store) { create(:store, code: 'promo_sweeper_store') }

  def build_order
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
  end

  def build_promotion(code)
    create(:promotion_with_order_adjustment, store: store, code: code, weighted_order_adjustment_amount: 10)
  end

  def reserved_row(order:, promotion:, reserved_at:, reserved_until: nil)
    PallasTrade::PromotionRedemption.create!(
      store: store, promotion: promotion, order: order, state: 'reserved', currency: order.currency,
      reserved_at: reserved_at, reserved_until: reserved_until
    )
  end

  it 'releases expired reservations（AC-003）' do
    order = build_order
    promotion = build_promotion('SWEEP1')
    redemption = reserved_row(order: order, promotion: promotion,
                              reserved_at: 3.hours.ago, reserved_until: 1.hour.ago)

    described_class.new.perform

    redemption.reload
    expect(redemption).to be_redemption_released
    expect(redemption.release_reason).to eq('reserved_timeout')
  end

  it 'uses the grace window when reserved_until is missing（AC-003）' do
    order = build_order
    promotion = build_promotion('SWEEP2')
    redemption = reserved_row(order: order, promotion: promotion, reserved_at: 3.hours.ago)

    described_class.new.perform

    expect(redemption.reload).to be_redemption_released
  end

  it 'leaves fresh reservations alone（AC-003）' do
    order = build_order
    promotion = build_promotion('SWEEP3')
    redemption = reserved_row(order: order, promotion: promotion,
                              reserved_at: 1.minute.ago, reserved_until: 1.hour.from_now)

    described_class.new.perform

    expect(redemption.reload).to be_redemption_reserved
  end

  it 'protects orders with payment evidence（AC-003）' do
    order = build_order
    order.update_columns(payment_total: 100, state: 'paid')
    promotion = build_promotion('SWEEP4')
    redemption = reserved_row(order: order, promotion: promotion,
                              reserved_at: 3.hours.ago, reserved_until: 1.hour.ago)

    described_class.new.perform

    expect(redemption.reload).to be_redemption_reserved
  end

  it 'is idempotent and logs sweep statistics（AC-007）' do
    order = build_order
    promotion = build_promotion('SWEEP5')
    reserved_row(order: order, promotion: promotion, reserved_at: 3.hours.ago, reserved_until: 1.hour.ago)

    allow(Rails.logger).to receive(:info).and_call_original

    expect(described_class.new.perform).to eq(1)
    expect(Rails.logger).to have_received(:info).with(/expire sweep scanned=1 released=1/)

    expect(described_class.new.perform).to eq(0)
    expect(Rails.logger).to have_received(:info).with(/expire sweep scanned=0 released=0/)
  end
end
