# frozen_string_literal: true

require 'spec_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 FR-033~036 / AC-034/035/036
# 售后父子单化：单订单/子订单售后 + 父单批量售后 + 归属视图
RSpec.describe '/api/v3/admin/orders/:order_id/return_authorizations (售后父子单化)', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:parent) { create(:order_with_line_items, store: store, user: user, currency: 'USD') }
  let(:reason) { create(:return_authorization_reason) }
  let(:stock_location) { create(:stock_location) }

  def add_shipped_units(order)
    order.line_items.each do |li|
      create(:inventory_unit, order: order, line_item: li, variant: li.variant, state: 'shipped')
    end
  end

  def build_child
    extra = create(:line_item, order: parent, price: 50)
    add_shipped_units(parent)
    result = PallasTrade::Orders::Splitter.call(order: parent, groups: { 'g1' => [extra.id] })
    child = result.value.first
    add_shipped_units(child)
    child
  end

  describe 'POST /api/v3/admin/orders/:order_id/return_authorizations' do
    it 'AC-034: 对单个子订单发起售后 → 创建 RA，归属该子订单' do
      child = build_child

      post "/api/v3/admin/orders/#{child.prefixed_id}/return_authorizations",
           params: { return_authorization_reason_id: reason.prefixed_id, stock_location_id: stock_location.prefixed_id, memo: '子订单售后' },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:order_id]).to eq(child.prefixed_id)
      expect(json_response[:order_parent_id]).to eq(parent.prefixed_id)
      expect(json_response[:order_is_child]).to be true
      expect(child.return_authorizations.count).to eq(1)
    end
  end

  describe 'POST /api/v3/admin/orders/:order_id/return_authorizations/bulk_from_parent' do
    it 'AC-035: 对整个父订单发起售后 → 批量创建其下全部子订单的 RA' do
      child = build_child

      post "/api/v3/admin/orders/#{parent.prefixed_id}/return_authorizations/bulk_from_parent",
           params: { return_authorization_reason_id: reason.prefixed_id, stock_location_id: stock_location.prefixed_id, memo: '父单售后' },
           headers: headers

      expect(response).to have_http_status(:created)
      data = json_response[:data]
      expect(data.length).to eq(2)
      ra_order_ids = data.map { |ra| ra[:order_id] }.sort
      expect(ra_order_ids).to eq([parent.prefixed_id, child.prefixed_id].sort)
    end

    it 'AC-035: 幂等 — 再次发起不重复创建（无新 RA 时返回明确错误）' do
      build_child

      post "/api/v3/admin/orders/#{parent.prefixed_id}/return_authorizations/bulk_from_parent",
           params: { return_authorization_reason_id: reason.prefixed_id, stock_location_id: stock_location.prefixed_id },
           headers: headers
      expect(response).to have_http_status(:created)

      post "/api/v3/admin/orders/#{parent.prefixed_id}/return_authorizations/bulk_from_parent",
           params: { return_authorization_reason_id: reason.prefixed_id, stock_location_id: stock_location.prefixed_id },
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('no_return_authorization_created')
      expect(PallasTrade::ReturnAuthorization.count).to eq(2)
    end
  end

  describe 'GET /api/v3/admin/orders/:order_id/return_authorizations' do
    it 'AC-036: 父订单视图汇总其自身 + 全部子订单的售后记录' do
      child = build_child
      create(:return_authorization, order: parent, reason: reason, stock_location: stock_location)
      create(:return_authorization, order: child, reason: reason, stock_location: stock_location)

      get "/api/v3/admin/orders/#{parent.prefixed_id}/return_authorizations", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data].length).to eq(2)

      child_ra = json_response[:data].find { |ra| ra[:order_id] == child.prefixed_id }
      expect(child_ra[:order_parent_id]).to eq(parent.prefixed_id)
      expect(child_ra[:order_is_child]).to be true
    end
  end
end
