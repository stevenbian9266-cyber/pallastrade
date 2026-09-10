# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot AC-005
# Store API 展示面：统一投影（`DiscountRendering#discounts_payload`）冻结后输出快照，
# 未冻结购物车仍输出实时定义（回归）。
RSpec.describe 'Store API discounts read the frozen snapshot', type: :request do
  include_context 'API v3 Store authenticated'

  let!(:promotion) do
    create(:promotion_with_order_adjustment, store: store, code: 'APISNAP10', name: 'API Snapshot Promo',
                                             weighted_order_adjustment_amount: 10)
  end

  def submitted_order
    order = create(:order_with_line_items, store: store, user: user,
                                           line_items_count: 1, line_items_price: 100, shipment_cost: 5)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
    order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.reload
  end

  def checkout_discounts(order)
    get "/api/v3/store/orders/#{order.prefixed_id}/checkout", headers: headers

    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)['discounts']
  end

  it 'returns the frozen name and code after the promotion is renamed and re-coded（AC-005）' do
    order = submitted_order
    order.pay!
    promotion.update!(name: 'Renamed Live', code: 'APISNAPNEW')

    discounts = checkout_discounts(order.reload)

    expect(discounts.size).to eq(1)
    expect(discounts.first['name']).to eq('API Snapshot Promo')
    expect(discounts.first['code']).to eq('apisnap10')
  end

  it 'keeps serving the live definition for an unfrozen order（AC-005 regression）' do
    order = submitted_order
    promotion.update!(name: 'Live Before Payment')

    discounts = checkout_discounts(order.reload)

    expect(discounts.first['name']).to eq('Live Before Payment')
  end
end
