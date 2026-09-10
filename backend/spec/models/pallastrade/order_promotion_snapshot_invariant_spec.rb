# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot AC-007
# Invariant：成交订单不受促销后续修改影响（改名 / 改 kind / 换码 / 改规则 / 删动作），
# 且取消订单仍保留快照（历史审计）。
RSpec.describe 'Order promotion snapshot invariant' do
  let!(:store) { create(:store, code: 'promo_snapshot_invariant_store') }

  let(:promotion) do
    create(:promotion_with_order_adjustment, store: store, code: 'INVARIANT10', name: 'Invariant Promo',
                                             weighted_order_adjustment_amount: 10)
  end

  let(:order) do
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
    order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.update_columns(completed_at: Time.current, state: 'complete')
    order.reload
    PallasTrade::Promotions::Snapshot::Freeze.call(order)
    order
  end

  def snapshot_of(order, promotion)
    order.order_promotions.reload.find_by(promotion_id: promotion.id)
  end

  def projected(order)
    line = PallasTrade::Promotions::Projection::DiscountProjection.for(order: order.reload).first
    [line&.name, line&.code, line&.kind]
  end

  it 'keeps the frozen name/code/kind after rename, kind change, code change and rule edits（AC-007）' do
    frozen_before = snapshot_of(order, promotion).attributes
    projected_before = projected(order)
    discount_total_before = order.reload.discount_total
    promo_code_before = order.promo_code

    promotion.update!(name: 'Totally Different')
    promotion.update!(kind: :automatic)
    promotion.promotion_rules.create!(type: 'PallasTrade::Promotion::Rules::ItemTotal')

    row = snapshot_of(order, promotion)
    expect(row.name).to eq('Invariant Promo')
    expect(row.code).to eq('invariant10')
    expect(row.kind).to eq('coupon_code')
    expect(row.attributes).to eq(frozen_before)
    expect(projected(order)).to eq(projected_before)
    expect(order.reload.discount_total).to eq(discount_total_before)
    expect(order.promo_code).to eq(promo_code_before)
  end

  it 'keeps the snapshot when the promotion actions are removed（AC-007 / R4）' do
    row = snapshot_of(order, promotion)
    frozen_before = row.attributes

    promotion.promotion_actions.destroy_all

    expect(snapshot_of(order, promotion).attributes).to eq(frozen_before)
    expect(snapshot_of(order, promotion).total_amount.to_d).to eq(-10.to_d)
  end

  it 'keeps the snapshot after the order is canceled（AC-007 / R5）' do
    order.update_columns(state: 'confirm')
    allow(order).to receive(:allow_cancel?).and_return(true)
    order.cancel!
    order.reload

    row = snapshot_of(order, promotion)
    expect(row).to be_frozen
    expect(row.name).to eq('Invariant Promo')
  end
end
