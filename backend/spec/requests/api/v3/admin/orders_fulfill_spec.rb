# frozen_string_literal: true

require 'spec_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 FR-031 / AC-031
# 管理后台已付款订单（含子订单）发货触发机制 — 子订单可单独触发发货，shipment 状态正确推进
RSpec.describe '/api/v3/admin/orders/:order_id/fulfillments/:id/fulfill (子订单发货)', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:parent) { create(:order_with_line_items, store: store, user: user, currency: 'USD') }

  it 'AC-031: 拆出的子订单可触发发货，shipment 状态推进为 shipped' do
    parent
    target = parent.line_items.first
    expect(target.inventory_units).not_to be_empty

    split_result = PallasTrade::Orders::Splitter.call(order: parent, groups: { 'g1' => [target.id] })
    expect(split_result).to be_success
    child = split_result.value.first
    expect(child.shipments.size).to eq(1)

    # 模拟子订单已付款并完成（拆单后正常 checkout 完成路径）
    create(:payment, amount: child.total, order: child, state: 'completed')
    child.update_columns(completed_at: Time.current, state: 'complete')
    expect(child.paid?).to be true
    expect(child.can_ship?).to be true
    expect(child.inventory_units.map(&:state)).to all(be_in(%w[on_hand backordered]))

    shipment = child.shipments.first
    shipment.update_columns(tracking: 'TRACK20260824')
    shipment.ready!
    expect(shipment.reload.state).to eq('ready')

    patch "/api/v3/admin/orders/#{child.prefixed_id}/fulfillments/#{shipment.prefixed_id}/fulfill", headers: headers

    expect(response).to have_http_status(:ok)
    expect(shipment.reload.state).to eq('shipped')
    # 发货后子订单可对其发起售后（FR-034 前置）
    expect(child.inventory_units.shipped).not_to be_empty
  end
end
