# frozen_string_literal: true

require 'spec_helper'

# PRD-20260830-checkout AC-008（submitted/pending 订单立即可见且按 store/user 隔离）
RSpec.describe 'Store Customer Orders API', type: :request do
  include_context 'API v3 Store guest'

  let(:store) { @default_store }

  it 'includes submitted pending orders and excludes another customer orders' do
    pending_order = create(
      :order,
      store: store,
      user: user,
      state: 'pending',
      status: 'placed',
      submitted_at: Time.current
    )
    create(
      :order,
      store: store,
      user: create(:user),
      state: 'pending',
      status: 'placed',
      submitted_at: Time.current
    )

    get '/api/v3/store/customers/me/orders', headers: bearer_headers

    expect(response).to have_http_status(:ok)
    expect(json_response[:data].map { |order| order[:id] }).to eq([pending_order.prefixed_id])
  end

  it 'excludes an order from another store even when the user is the same' do
    other_store = create(:store, code: "other_#{SecureRandom.hex(4)}")
    create(
      :order,
      store: other_store,
      user: user,
      state: 'pending',
      status: 'placed',
      submitted_at: Time.current
    )

    get '/api/v3/store/customers/me/orders', headers: bearer_headers

    expect(response).to have_http_status(:ok)
    expect(json_response[:data]).to be_empty
  end
end
