# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Order payment sessions (Store API)', type: :request do
  include_context 'API v3 Store authenticated'

  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }

  def completed_balance_due_order(owner: user)
    order = create(:order_with_line_items, store: store, user: owner, shipment_cost: 0)
    order.update_columns(
      state: 'complete',
      completed_at: Time.current,
      payment_state: 'balance_due',
      payment_total: 0
    )
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def pending_standard_order(owner: user)
    order = create(:order_with_line_items, store: store, user: owner, shipment_cost: 0)
    order.update_columns(state: 'pending', payment_state: nil, completed_at: nil)
    order.reload
  end

  describe 'POST /api/v3/store/orders/:order_id/payment_sessions' do
    it 'allows the customer to pay an owned completed order with a balance due' do
      order = completed_balance_due_order

      post "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['order_id']).to eq(order.prefixed_id)
    end

    it 'does not expose another customer order' do
      order = completed_balance_due_order(owner: create(:user))

      post "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  # 回归：嵌套路由下 find_order 必须解析 :order_id（params[:id] 是子资源 id，
  # 若误用会按 ps_ 会话 id 查找 Order → 404）。PRD-20260831-payments-stripe 支付链路发现。
  describe 'nested :order_id resolution' do
    it 'completes a payment session on the nested complete route' do
      order = completed_balance_due_order
      session = payment_method.create_payment_session(order: order, amount: order.total)
      session.save!

      patch "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions/#{session.prefixed_id}/complete",
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(session.reload).to be_completed
    end

    # 回归：前端 active complete 后必须驱动订单完成（否则 webhook 对已
    # completed 会话提前返回 → 订单停留 pending）。
    it 'completes the order after the nested complete (standard flow)' do
      order = pending_standard_order
      create(:payment, order: order, payment_method: payment_method,
                       amount: order.total, state: 'completed')
      session = payment_method.create_payment_session(order: order, amount: order.total)
      session.save!

      patch "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions/#{session.prefixed_id}/complete",
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(session.reload).to be_completed
      expect(order.reload).to be_completed
      expect(order.payment_state).to eq('paid')
    end

    # P0-0 回归：同一会话重复 complete 必须幂等（不重复建 Payment / 不重复 finalize）。
    it 'is idempotent when the same session is completed twice' do
      order = pending_standard_order
      create(:payment, order: order, payment_method: payment_method,
                       amount: order.total, state: 'completed')
      session = payment_method.create_payment_session(order: order, amount: order.total)
      session.save!

      patch "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions/#{session.prefixed_id}/complete",
            headers: headers
      expect(response).to have_http_status(:ok)
      payments_after_first = order.reload.payments.count
      completed_at = order.reload.completed_at

      patch "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions/#{session.prefixed_id}/complete",
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(order.reload.payments.count).to eq(payments_after_first)
      expect(order.completed_at).to eq(completed_at)
    end

    it 'shows a payment session on the nested show route' do
      order = completed_balance_due_order
      session = payment_method.create_payment_session(order: order, amount: order.total)
      session.save!

      get "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions/#{session.prefixed_id}",
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['id']).to eq(session.prefixed_id)
    end
  end

  # CHK-P1-5 (PRD §12): quote-conflict 409 —— expected_version/expected_price_version 比对。
  describe 'POST quote-conflict 409' do
    def quoted_pending_order
      order = pending_standard_order
      PallasTrade::OrderCheckout::Recalculate.call(order: order)
      order.reload
    end

    it 'returns 201 when expected quote matches the active quote (AC-501)' do
      order = quoted_pending_order

      post "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions",
           params: {
             payment_method_id: payment_method.prefixed_id,
             expected_version: order.checkout_version,
             expected_price_version: order.price_version
           },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(order.reload.payment_sessions.count).to eq(1)
    end

    it 'returns 409 checkout_version_conflict with compact latest quote when version mismatches (AC-502/503)' do
      order = quoted_pending_order

      post "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions",
           params: {
             payment_method_id: payment_method.prefixed_id,
             expected_version: order.checkout_version + 1,
             expected_price_version: order.price_version
           },
           headers: headers

      expect(response).to have_http_status(:conflict)
      body = JSON.parse(response.body)
      expect(body['error']['code']).to eq('checkout_version_conflict')
      latest = body['error']['details']['latest']
      expect(latest['version']).to eq(order.checkout_version)
      expect(latest['price_version']).to eq(order.price_version)
      expect(latest['amount_due']).to eq(order.amount_due.to_s)
      expect(order.reload.payment_sessions.count).to eq(0)
    end
  end
end
