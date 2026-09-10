# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot AC-006
# Rails Admin 订单促销面板：成交后展示快照（改名/改类型徽章不影响历史展示）。
RSpec.describe 'Admin order promotions panel reads the snapshot', type: :request do
  let!(:store) { create(:store, code: 'admin_order_snapshot_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let!(:promotion) do
    create(:promotion_with_order_adjustment, store: store, code: 'ADMINSNAP', name: 'Admin Snapshot Promo',
                                             weighted_order_adjustment_amount: 10)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::OrdersController).to receive(:current_store).and_return(store)
  end

  def completed_order
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
    order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.update_columns(completed_at: Time.current, state: 'complete')
    order.reload
  end

  it 'renders the frozen promotion name after a rename（AC-006）' do
    order = completed_order
    PallasTrade::Promotions::Snapshot::Freeze.call(order)
    promotion.update!(name: 'Renamed After Freeze')

    sign_in_as_superuser
    get "/admin/orders/#{order.prefixed_id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Admin Snapshot Promo')
    expect(response.body).not_to include('Renamed After Freeze')
  end

  it 'falls back to the live definition for an unfrozen order（AC-006 regression）' do
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
    order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.reload

    sign_in_as_superuser
    get "/admin/orders/#{order.prefixed_id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(promotion.name)
  end
end
