# frozen_string_literal: true

require 'spec_helper'

# PRD-20260826-payments-实施-p1-数据模型与语义方法
# AC-008：OrderSerializer 输出 parent_id / children_ids / is_parent / is_child / is_single
RSpec.describe 'Order serializer parent/child fields', type: :request do
  include_context 'API v3 Store authenticated'

  it 'exposes parent/child/single fields for a single (non-split) order' do
    order = create(:order, store: store, user: user, state: 'complete', completed_at: Time.current)

    get "/api/v3/store/customers/me/orders/#{order.prefixed_id}", headers: headers

    expect(response).to have_http_status(:ok)
    attributes = JSON.parse(response.body)
    expect(attributes['parent_id']).to be_nil
    expect(attributes['children_ids']).to eq([])
    expect(attributes['is_parent']).to be false
    expect(attributes['is_child']).to be false
    expect(attributes['is_single']).to be true
  end

  it 'exposes parent/child fields for a parent order with children' do
    parent = create(:order, store: store, user: user, state: 'complete', completed_at: Time.current)
    child = create(:order, store: store, user: user, parent: parent,
                           state: 'complete', completed_at: Time.current)

    get "/api/v3/store/customers/me/orders/#{parent.prefixed_id}", headers: headers

    expect(response).to have_http_status(:ok)
    attributes = JSON.parse(response.body)
    expect(attributes['is_parent']).to be true
    expect(attributes['is_child']).to be false
    expect(attributes['is_single']).to be false
    expect(attributes['children_ids']).to eq([child.prefixed_id])
  end

  it 'exposes parent fields for a child order' do
    parent = create(:order, store: store, user: user, state: 'complete', completed_at: Time.current)
    child = create(:order, store: store, user: user, parent: parent,
                           state: 'complete', completed_at: Time.current)

    get "/api/v3/store/customers/me/orders/#{child.prefixed_id}", headers: headers

    expect(response).to have_http_status(:ok)
    attributes = JSON.parse(response.body)
    expect(attributes['parent_id']).to eq(parent.prefixed_id)
    expect(attributes['is_child']).to be true
    expect(attributes['is_single']).to be false
  end

  # PRD-20260827-payments P3 AC-008：父订单序列化器金额/状态走聚合派生
  # 轻量构建带金额订单：先以 cart 状态加行项目（避免 complete 触发库存校验），再 update_columns 模拟完成态
  def paid_order_with_total(total: 10, **attrs)
    order = create(:order, store: store, user: user, **attrs)
    create(:line_item, order: order, price: total)
    order.update_columns(
      state: 'complete', completed_at: Time.current,
      item_total: total, adjustment_total: 0, shipment_total: 0, total: total,
      payment_total: total, payment_state: 'paid', shipment_state: 'ready', item_count: 1
    )
    order
  end

  it 'AC-008 parent order exposes aggregated totals and states' do
    parent = paid_order_with_total
    paid_order_with_total(parent: parent)
    parent.reload # 重置 children 关联缓存，确保聚合基于 DB 最新

    get "/api/v3/store/customers/me/orders/#{parent.prefixed_id}", headers: headers

    expect(response).to have_http_status(:ok)
    attributes = JSON.parse(response.body)
    expect(attributes['is_parent']).to be true
    expect(attributes['total']).to eq(parent.combined_total.to_s)
    expect(attributes['display_total']).to eq(parent.display_combined_total.to_s)
    expect(attributes['amount_due']).to eq(parent.combined_amount_due.to_s)
    expect(attributes['payment_status']).to eq('paid')
    expect(attributes['fulfillment_status']).to eq('ready')
  end

  it 'AC-008 single order serializer keeps own totals (no aggregation)' do
    order = paid_order_with_total

    get "/api/v3/store/customers/me/orders/#{order.prefixed_id}", headers: headers

    expect(response).to have_http_status(:ok)
    attributes = JSON.parse(response.body)
    expect(attributes['is_single']).to be true
    expect(attributes['total']).to eq(order.combined_total.to_s)
    expect(attributes['display_total']).to eq(order.display_combined_total.to_s)
    expect(attributes['amount_due']).to eq(order.combined_amount_due.to_s)
    expect(attributes['payment_status']).to eq('paid')
    expect(attributes['fulfillment_status']).to eq('ready')
  end
end
