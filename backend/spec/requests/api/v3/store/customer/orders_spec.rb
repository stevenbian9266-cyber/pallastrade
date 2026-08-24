# frozen_string_literal: true

require 'spec_helper'

# PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台
# AC-001/AC-002/AC-003：?scope= 按订单状态过滤顾客订单列表
RSpec.describe 'GET /api/v3/store/customer/orders with scope', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:path) { '/api/v3/store/customer/orders' }

  # 各状态订单
  let!(:completed) do
    create(:completed_order_with_totals, store: store, user: user)
  end
  let!(:unpaid) do
    create(:order_with_totals, store: store, user: user,
                               status: 'placed', payment_state: 'balance_due',
                               completed_at: nil)
  end
  let!(:processing) do
    create(:order_ready_to_ship, store: store, user: user)
  end
  let!(:shipped) do
    create(:shipped_order, store: store, user: user)
  end
  let!(:canceled) do
    create(:order_with_totals, store: store, user: user,
                               status: 'canceled', completed_at: nil)
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
