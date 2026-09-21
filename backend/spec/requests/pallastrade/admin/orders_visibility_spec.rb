# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout-订单可见性补齐-后台列表显示未完成订单-支付失败就地入口-游客最近一笔订单入口
#   AC-001 / AC-002 / AC-003
#
# 背景：`/admin/orders` 原用 `base_scope.complete`（= `completed_at IS NOT NULL`），
# 而 `completed_at` 只在 `finalize!` 之后写入 → 顾客「点了支付未付成」的 pending 订单
# 与「已支付未 finalize」的订单在运营视图**完全不可见**（本地实测 7 + 3 张）。
# 本口径改为「已提交 ∪ 已完成」，并**排除** `state=cart` 草稿（Order 与购物车同表）。
RSpec.describe 'Admin orders list visibility', type: :request do
  let!(:store) { create(:store, code: 'admin_order_visibility_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::OrdersController).to receive(:current_store).and_return(store)
  end

  # 已提交但未 finalize —— 顾客点了支付、尚未付成（最需要运营跟进的单）
  def pending_order(number)
    order = create(:order_with_line_items, store: store, number: number)
    order.update_columns(state: 'pending', submitted_at: Time.current, completed_at: nil)
    order
  end

  # 已支付但尚未 finalize（旧口径下同样不可见）
  def paid_unfinalized_order(number)
    order = create(:order_with_line_items, store: store, number: number)
    order.update_columns(state: 'paid', submitted_at: Time.current, completed_at: nil)
    order
  end

  # 未提交的购物车草稿（submitted_at 与 completed_at 均为 NULL）—— 不应出现在运营列表
  def draft_cart_order(number)
    order = create(:order_with_line_items, store: store, number: number)
    order.update_columns(state: 'cart', submitted_at: nil, completed_at: nil)
    order
  end

  def finalized_order(number)
    order = create(:order_with_line_items, store: store, number: number)
    order.update_columns(state: 'complete', submitted_at: Time.current, completed_at: Time.current)
    order
  end

  # PRD-20260920-checkout-订单可见性补齐 AC-001
  it 'shows submitted-but-unfinished orders: pending and paid-unfinalized' do
    pending = pending_order('R900000001')
    paid = paid_unfinalized_order('R900000002')

    sign_in_as_superuser
    get '/admin/orders'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(pending.number),
                                'pending（已提交未付成）订单必须出现在后台列表 —— 这正是本次修复的核心'
    expect(response.body).to include(paid.number),
                                '已支付但未 finalize 的订单同样必须可见（旧口径下也不可见）'
  end

  # PRD-20260920-checkout-订单可见性补齐 AC-002
  it 'hides unsubmitted cart drafts so the list is not flooded with checkout rows' do
    draft = draft_cart_order('R900000003')

    sign_in_as_superuser
    get '/admin/orders'

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(draft.number),
                                    'state=cart 且 submitted_at 为 NULL 的草稿属未提交数据，不应污染运营视图'
  end

  # PRD-20260920-checkout-订单可见性补齐 AC-003
  it 'matches the storefront customer-orders visibility predicate exactly' do
    visible_pending = pending_order('R900000004')
    visible_finalized = finalized_order('R900000005')
    hidden_draft = draft_cart_order('R900000006')

    # 前台口径（Api::V3::Store::Customer::OrdersController#scope）：
    #   where.not(submitted_at: nil).or(complete)
    predicate = store.orders.where.not(submitted_at: nil).or(store.orders.complete)
    expected_numbers = predicate.pluck(:number)

    expect(expected_numbers).to include(visible_pending.number, visible_finalized.number)
    expect(expected_numbers).not_to include(hidden_draft.number)

    sign_in_as_superuser
    get '/admin/orders'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible_pending.number, visible_finalized.number)
    expect(response.body).not_to include(hidden_draft.number),
                                        '后台可见集合必须与前台 customer orders 口径一致（避免跨层漂移）'
  end
end
