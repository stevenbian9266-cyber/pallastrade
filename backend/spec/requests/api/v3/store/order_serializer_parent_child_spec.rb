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
end
