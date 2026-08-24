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

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化
# AC-007/009：父子单结构 — Store API 返回父子关系 + children/parent 端点
RSpec.describe 'GET /api/v3/store/customers/me/orders/:id/children|parent', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:path) { '/api/v3/store/customers/me/orders' }

  # show 端点走 scope（默认仅 complete 订单），故父子测试订单需置为 complete
  def completed_order(attrs = {})
    order = create(:order_with_line_items, store: store, user: user, currency: 'USD', **attrs)
    order.update_columns(completed_at: Time.current, status: 'placed', payment_state: 'paid')
    order
  end

  let!(:parent) { completed_order }
  let!(:child1) { completed_order(parent: parent) }
  let!(:child2) { completed_order(parent: parent) }

  it 'AC-009: 订单详情响应包含父子关系字段' do
    get "#{path}/#{parent.prefixed_id}", headers: headers
    expect(response).to have_http_status(:ok)
    data = json_response
    expect(data['parent_id']).to be_nil
    expect(data['children_ids']).to contain_exactly(child1.prefixed_id, child2.prefixed_id)
    expect(data['is_parent']).to be true
    expect(data['is_child']).to be false
    expect(data['is_single']).to be false
  end

  it 'AC-007/009: 未拆单订单父=子（is_single=true，无 parent/children）' do
    single = completed_order
    get "#{path}/#{single.prefixed_id}", headers: headers
    expect(response).to have_http_status(:ok)
    data = json_response
    expect(data['parent_id']).to be_nil
    expect(data['children_ids']).to eq([])
    expect(data['is_parent']).to be false
    expect(data['is_child']).to be false
    expect(data['is_single']).to be true
  end

  it 'AC-009: GET /orders/:id/children 返回父订单的子订单列表' do
    get "#{path}/#{parent.prefixed_id}/children", headers: headers
    expect(response).to have_http_status(:ok)
    expect(json_response['data'].map { |o| o['id'] })
      .to contain_exactly(child1.prefixed_id, child2.prefixed_id)
  end

  it 'AC-009: GET /orders/:id/parent 返回子订单的父订单' do
    get "#{path}/#{child1.prefixed_id}/parent", headers: headers
    expect(response).to have_http_status(:ok)
    expect(json_response['id']).to eq(parent.prefixed_id)
  end

  it 'AC-009: 未拆单订单 parent 返回 404' do
    single = completed_order
    get "#{path}/#{single.prefixed_id}/parent", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'AC-009: 不能访问其他用户的父子订单' do
    other = create(:order_with_line_items, store: store, user: create(:user))
    get "#{path}/#{other.prefixed_id}/children", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{path}/#{other.prefixed_id}/parent", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
