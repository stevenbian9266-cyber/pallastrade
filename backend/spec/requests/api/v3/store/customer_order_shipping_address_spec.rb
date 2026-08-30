# frozen_string_literal: true

require 'rails_helper'

# PRD-20260829-checkout（订单模块收货信息独立填写）
# AC-003/AC-004：合并支付收货步骤更新订单收货地址（仅未支付订单可改）
RSpec.describe 'PATCH /api/v3/store/customers/me/orders/:order_id/shipping_address', type: :request do
  include_context 'API v3 Store authenticated'

  # 含地址/shipment、金额固化的未支付订单（复用 P4/P5 构造）
  def unpaid_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    order.shipments.each do |s|
      s.shipping_rates.destroy_all
      s.add_shipping_method(create(:free_shipping_method), true)
    end
    order.next until order.payment? || order.complete? || order.errors.any?
    order.update_columns(state: 'cart', completed_at: nil)
    order.line_items.reload
    PallasTrade::OrderUpdater.new(order).update
    order.reload
    order
  end

  def address_params(overrides = {})
    {
      first_name: 'Ada',
      last_name: 'Lovelace',
      address1: '12 Analytical Engine Way',
      city: 'New York',
      postal_code: '10118',
      country_iso: 'US',
      state_abbr: 'NY'
    }.merge(overrides)
  end

  describe 'AC-003 — update shipping address in place' do
    it 'updates the order shipping_address and returns the refreshed order' do
      order = unpaid_order

      patch "/api/v3/store/customers/me/orders/#{order.prefixed_id}/shipping_address",
            params: { shipping_address: address_params },
            headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['id']).to eq(order.prefixed_id)
      expect(order.reload.shipping_address).to be_present
      expect(order.shipping_address.first_name).to eq('Ada')
      expect(order.shipping_address.address1).to eq('12 Analytical Engine Way')
      # 订单号/状态不变（不重置 checkout 状态机）
      expect(body['number']).to eq(order.number)
    end

    it 'syncs the shipment address_id with the updated address' do
      order = unpaid_order

      patch "/api/v3/store/customers/me/orders/#{order.prefixed_id}/shipping_address",
            params: { shipping_address: address_params },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(order.reload.shipments.map(&:address_id).uniq)
        .to eq([order.shipping_address.id])
    end
  end

  describe 'AC-003 — reference a saved address via shipping_address_id' do
    it 'points the order at one of the user\'s own saved addresses' do
      order = unpaid_order
      saved = create(:address, user: user)

      patch "/api/v3/store/customers/me/orders/#{order.prefixed_id}/shipping_address",
            params: { shipping_address_id: saved.prefixed_id },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(order.reload.shipping_address_id).to eq(saved.id)
    end

    it 'ignores a foreign address id (IDOR-safe) and keeps the current address' do
      order = unpaid_order
      foreign = create(:address, user: create(:user))

      patch "/api/v3/store/customers/me/orders/#{order.prefixed_id}/shipping_address",
            params: { shipping_address_id: foreign.prefixed_id },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(order.reload.shipping_address_id).not_to eq(foreign.id)
    end
  end

  describe 'AC-004 — only unpaid orders are editable' do
    it 'rejects a paid order with 422 order_not_editable' do
      order = unpaid_order
      order.update_column(:payment_total, order.total)

      patch "/api/v3/store/customers/me/orders/#{order.prefixed_id}/shipping_address",
            params: { shipping_address: address_params },
            headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body.dig('error', 'code')).to eq('order_not_editable')
    end

    it 'rejects an invalid address with 422' do
      order = unpaid_order

      patch "/api/v3/store/customers/me/orders/#{order.prefixed_id}/shipping_address",
            params: { shipping_address: address_params(address1: '') },
            headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'authorization' do
    it 'returns 404 for another user\'s order' do
      other = create(:user)
      order = create(:order_with_line_items, store: store, user: other, shipment_cost: 0)

      patch "/api/v3/store/customers/me/orders/#{order.prefixed_id}/shipping_address",
            params: { shipping_address: address_params },
            headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 without a token' do
      order = unpaid_order

      patch "/api/v3/store/customers/me/orders/#{order.prefixed_id}/shipping_address",
            params: { shipping_address: address_params },
            headers: api_key_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
