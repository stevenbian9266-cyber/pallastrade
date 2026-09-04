# frozen_string_literal: true

require 'rails_helper'

# CHK-P1-1A: GET /api/v3/store/orders/:id/checkout（只读）。
RSpec.describe 'Order checkout (Store API, read-only projection)', type: :request do
  include_context 'API v3 Store authenticated'

  def submitted_order(owner: user)
    order = create(:order_with_line_items, store: store, user: owner,
                                           line_items_price: 100, shipment_cost: 5)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  describe 'GET /api/v3/store/orders/:order_id/checkout' do
    it 'returns 200 with the checkout projection for an authenticated owner (AC-106)' do
      order = submitted_order

      get "/api/v3/store/orders/#{order.prefixed_id}/checkout", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['id']).to eq(order.prefixed_id)
      expect(body['state']).to eq('pending')
      expect(body['items']).to be_an(Array)
      expect(body['total'].to_s).to eq(order.total.to_s)
    end

    it 'is accessible to guests via the order token (AC-106)' do
      order = submitted_order

      get "/api/v3/store/orders/#{order.prefixed_id}/checkout",
          headers: api_key_headers.merge('x-pallastrade-token' => order.token)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['id']).to eq(order.prefixed_id)
    end

    it 'returns 404 for a non-existent order' do
      get '/api/v3/store/orders/or_doesnotexist/checkout', headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'does not expose another customer order (store/user isolation → 404)' do
      other_user = create(:user)
      other_order = submitted_order(owner: other_user)

      get "/api/v3/store/orders/#{other_order.prefixed_id}/checkout", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'does not expose legacy checkout-state orders via the order API (AC-105 boundary)' do
      legacy = create(:order_with_line_items, store: store, user: user,
                                              line_items_price: 50, shipment_cost: 0)
      legacy.update_columns(state: 'cart', submitted_at: nil, completed_at: nil)

      get "/api/v3/store/orders/#{legacy.prefixed_id}/checkout", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'still projects a completed order (AC-104)' do
      order = submitted_order
      order.update_columns(state: 'complete', status: 'complete', completed_at: Time.current,
                           payment_state: 'paid')
      order.reload

      get "/api/v3/store/orders/#{order.prefixed_id}/checkout", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['state']).to eq('complete')
      expect(body['completed_at']).to be_present
    end

    it 'has zero side effects on GET (AC-107)' do
      order = submitted_order
      order_attrs = order.reload.attributes
      session_count = PallasTrade::PaymentSession.count
      payment_count = PallasTrade::Payment.count

      get "/api/v3/store/orders/#{order.prefixed_id}/checkout", headers: headers

      expect(response).to have_http_status(:ok)
      expect(order.reload.attributes).to eq(order_attrs)
      expect(PallasTrade::PaymentSession.count).to eq(session_count)
      expect(PallasTrade::Payment.count).to eq(payment_count)
    end
  end

  describe 'PATCH /api/v3/store/orders/:order_id/checkout (CHK-P1-1B mutation facade)' do
    it 'updates contact and returns the latest CheckoutView' do
      order = submitted_order

      patch "/api/v3/store/orders/#{order.prefixed_id}/checkout",
            params: { contact: { email: 'patched@example.com' } }, headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['email']).to eq('patched@example.com')
      expect(order.reload.email).to eq('patched@example.com')
    end

    it 'updates shipping address and returns the latest CheckoutView' do
      order = submitted_order

      patch "/api/v3/store/orders/#{order.prefixed_id}/checkout",
            params: { shipping_address: { first_name: 'NewFirst', last_name: 'NewLast' } }, headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['shipping_address']['first_name']).to eq('NewFirst')
      expect(order.reload.ship_address.firstname).to eq('NewFirst')
    end

    it 'selects a delivery rate and reflects the recomputed shipping total' do
      order = submitted_order
      shipment = order.shipments.first
      old_shipment_total = order.shipment_total
      rate2 = create(:shipping_rate, shipment: shipment,
                                     shipping_method: create(:shipping_method), cost: BigDecimal('20'))
      before_total = order.amount_due

      patch "/api/v3/store/orders/#{order.prefixed_id}/checkout",
            params: { delivery_rate_id: rate2.prefixed_id }, headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(shipment.reload.selected_shipping_rate&.id).to eq(rate2.id)
      # 新 rate cost(20) 取代原 shipment 成本（rate2 增量 = 20 - old_total）
      expect(order.reload.amount_due).to eq(before_total - old_shipment_total + BigDecimal('20'))
      expect(body['delivery_total'].to_s).to eq(order.shipment_total.to_s)
    end

    it 'rejects an empty mutation body' do
      order = submitted_order

      patch "/api/v3/store/orders/#{order.prefixed_id}/checkout", params: {}, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects mutation on a completed order (403 by order :update ability)' do
      order = submitted_order
      order.update_columns(state: 'complete', status: 'complete', completed_at: Time.current,
                           payment_state: 'paid')
      order.reload

      patch "/api/v3/store/orders/#{order.prefixed_id}/checkout",
            params: { contact: { email: 'x@example.com' } }, headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(order.reload.email).not_to eq('x@example.com')
    end

    it 'does not mutate another customer order (404)' do
      other = create(:user)
      other_order = submitted_order(owner: other)

      patch "/api/v3/store/orders/#{other_order.prefixed_id}/checkout",
            params: { contact: { email: 'y@example.com' } }, headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
