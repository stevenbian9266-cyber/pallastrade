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
end
