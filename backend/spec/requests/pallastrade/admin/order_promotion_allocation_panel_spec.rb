# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch4b-refund-allocation AC-008
# 后台订单页只读「退款分摊预览」（架构 §101）：原金额 / 分摊优惠 / 可退金额。
RSpec.describe 'Admin order refund allocation panel', type: :request do
  let!(:store) { create(:store, code: 'admin_allocation_panel_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let!(:promotion) do
    create(:promotion_with_order_adjustment, store: store, code: 'PANELALLOC', name: 'Panel Allocation Promo',
                                             weighted_order_adjustment_amount: 30)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::OrdersController).to receive(:current_store).and_return(store)
  end

  def completed_order
    order = create(:order_with_line_items, store: store, line_items_count: 2, line_items_price: 100,
                                           shipment_cost: 50)
    order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.update_columns(completed_at: Time.current, state: 'complete')
    order.reload
    PallasTrade::Promotions::Snapshot::Freeze.call(order)
    order
  end

  it 'renders the read-only allocation preview with original / allocated / refundable amounts（AC-008）' do
    order = completed_order
    sign_in_as_superuser

    get "/admin/orders/#{order.prefixed_id}"

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include('Refund allocation preview')
    expect(body).to include(order.line_items.first.name)
    # 每行 100，订单级折扣 30 按 50/50 分摊 → 15.00
    expect(body).to include('15.00')
    expect(body).to include('Panel Allocation Promo')
  end

  it 'keeps showing the frozen promotion name after a rename（AC-008 / batch4a 联动）' do
    order = completed_order
    promotion.update!(name: 'Renamed After Freeze')
    sign_in_as_superuser

    get "/admin/orders/#{order.prefixed_id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Panel Allocation Promo')
    expect(response.body).not_to include('Renamed After Freeze')
  end

  it 'renders no preview for an order without promotions（AC-008）' do
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
    sign_in_as_superuser

    get "/admin/orders/#{order.prefixed_id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Refund allocation preview')
  end
end
