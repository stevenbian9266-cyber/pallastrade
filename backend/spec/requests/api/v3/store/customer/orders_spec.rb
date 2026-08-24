# frozen_string_literal: true

require 'spec_helper'

# PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台
# AC-001/AC-002/AC-003：?scope= 按订单状态过滤顾客订单列表
RSpec.describe 'GET /api/v3/store/customer/orders with scope', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:path) { '/api/v3/store/customers/me/orders' }

  # 用 order_with_line_items（updater 重算 total），再显式覆盖状态字段，
  # 避免依赖 factory 派生（shipped_order 不重算 order.fulfillment_status 等）。
  def order_with(completed_at:, payment_state:, fulfillment_status:, status:)
    order = create(:order_with_line_items, store: store, user: user,
                                           currency: 'USD', status: 'placed',
                                           payment_state: 'balance_due', completed_at: nil)
    order.update_columns(
      completed_at: completed_at,
      payment_state: payment_state,
      fulfillment_status: fulfillment_status,
      status: status
    )
    order
  end

  # 各状态订单
  let!(:completed) do
    order_with(completed_at: Time.current, payment_state: 'paid',
               fulfillment_status: nil, status: 'placed')
  end
  let!(:unpaid) do
    order_with(completed_at: nil, payment_state: 'balance_due',
               fulfillment_status: nil, status: 'placed')
  end
  let!(:processing) do
    order_with(completed_at: nil, payment_state: 'paid',
               fulfillment_status: 'ready', status: 'placed')
  end
  let!(:shipped) do
    order_with(completed_at: nil, payment_state: 'paid',
               fulfillment_status: 'shipped', status: 'placed')
  end
  let!(:canceled) do
    order_with(completed_at: nil, payment_state: 'balance_due',
               fulfillment_status: nil, status: 'canceled')
  end

  def ids_for(params = {})
    get path, params: params, headers: headers
    expect(response).to have_http_status(:ok)
    json_response['data'].map { |o| o['id'] }
  end

  it 'defaults to completed orders when no scope is given' do
    expect(ids_for).to eq([completed.prefixed_id])
  end

  it 'scope=unpaid returns placed-but-unpaid orders only' do
    expect(ids_for(scope: 'unpaid')).to eq([unpaid.prefixed_id])
  end

  it 'scope=processing returns paid-but-not-shipped orders' do
    expect(ids_for(scope: 'processing')).to eq([processing.prefixed_id])
  end

  it 'scope=shipped returns shipped orders only' do
    expect(ids_for(scope: 'shipped')).to eq([shipped.prefixed_id])
  end

  it 'scope=canceled returns canceled orders only' do
    expect(ids_for(scope: 'canceled')).to eq([canceled.prefixed_id])
  end

  it 'scope=all returns every order regardless of status' do
    expect(ids_for(scope: 'all')).to contain_exactly(
      completed.prefixed_id, unpaid.prefixed_id, processing.prefixed_id,
      shipped.prefixed_id, canceled.prefixed_id
    )
  end

  it 'does not leak other users orders' do
    other = create(:completed_order_with_totals, store: store, user: create(:user))
    expect(ids_for(scope: 'all')).not_to include(other.prefixed_id)
  end
end
