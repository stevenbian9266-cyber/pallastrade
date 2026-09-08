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

  # PRD-20260908-checkout-商城前台-order AC-001：订单历史默认按创建时间由近到远
  # （混合「已提交未支付」与「已完成」订单，created_at 依次递增 → 返回倒序）
  it 'returns order history newest-first by created_at by default' do
    oldest = create(
      :order,
      store: store,
      user: user,
      state: 'pending',
      status: 'placed',
      submitted_at: 3.days.ago,
      created_at: 3.days.ago
    )
    middle = create(
      :order,
      store: store,
      user: user,
      state: 'pending',
      status: 'placed',
      submitted_at: 2.days.ago,
      created_at: 2.days.ago
    )
    newest = create(
      :order,
      store: store,
      user: user,
      completed_at: 1.day.ago,
      created_at: 1.day.ago
    )

    get '/api/v3/store/customers/me/orders', headers: bearer_headers

    expect(response).to have_http_status(:ok)
    expect(json_response[:data].map { |order| order[:id] }).to eq([newest.prefixed_id, middle.prefixed_id, oldest.prefixed_id])
  end

  # PRD-20260908-checkout-商城前台-order AC-002：默认排序后归属/状态隔离不回归
  # （另一用户、另一店铺订单仍不出现）
  it 'keeps ownership isolation while ordering by created_at' do
    mine = create(:order, store: store, user: user, completed_at: 1.hour.ago, created_at: 1.hour.ago)
    create(:order, store: store, user: create(:user), completed_at: 2.hours.ago, created_at: 2.hours.ago)
    create(
      :order,
      store: create(:store, code: "other_#{SecureRandom.hex(4)}"),
      user: user,
      completed_at: 30.minutes.ago,
      created_at: 30.minutes.ago
    )

    get '/api/v3/store/customers/me/orders', headers: bearer_headers

    expect(response).to have_http_status(:ok)
    expect(json_response[:data].map { |order| order[:id] }).to eq([mine.prefixed_id])
  end

  # PRD-20260908-checkout-商城前台-order AC-003：客户端显式 sort 参数仍优先于默认 created_at 排序
  it 'lets an explicit sort param override the default ordering' do
    first = create(
      :order,
      store: store,
      user: user,
      number: 'R100000001',
      completed_at: 1.day.ago,
      created_at: 1.day.ago
    )
    second = create(
      :order,
      store: store,
      user: user,
      number: 'R100000002',
      completed_at: 2.days.ago,
      created_at: 2.days.ago
    )
    third = create(
      :order,
      store: store,
      user: user,
      number: 'R100000003',
      completed_at: 3.days.ago,
      created_at: 3.days.ago
    )

    get '/api/v3/store/customers/me/orders?sort=-number', headers: bearer_headers

    expect(response).to have_http_status(:ok)
    # 默认 created_at 倒序本应为 first→second→third；显式 -number 使第三单（最大单号）在前
    expect(json_response[:data].map { |order| order[:number] }).to eq([third.number, second.number, first.number])
  end
end
