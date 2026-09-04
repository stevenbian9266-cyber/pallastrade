# frozen_string_literal: true

require 'rails_helper'

# P0-3 (PRD FR-031/FR-032): legacy cart 域支付会话创建 = PaymentSessions::Start 委托。
#   - 连续两次 POST（双击/retry）→ 复用同一 active 会话（同一 provider 意图）
#   - 结果带稳定 idempotency_key（无随机）
RSpec.describe 'Cart payment sessions (Store API, cart domain)', type: :request do
  include_context 'API v3 Store authenticated'

  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true) }

  # legacy 一页式 checkout 的购物车 = Order 行 state=cart（路由 /carts/:cart_id/payment_sessions 的 legacy 资源）
  def legacy_cart_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0, line_items_price: 100)
    order.update_columns(state: 'cart', completed_at: nil, submitted_at: nil, payment_state: nil, payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def create_session_headers(order)
    headers.merge('x-pallastrade-token' => order.token)
  end

  describe 'POST /api/v3/store/carts/:cart_id/payment_sessions' do
    it 'creates a payment session through PaymentSessions::Start with a stable idempotency key' do
      order = legacy_cart_order

      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: create_session_headers(order)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['order_id']).to eq(order.prefixed_id)

      session = PallasTrade::PaymentSession.find_by_prefix_id!(body['id'])
      expect(session.external_data['idempotency_key']).to be_present
      expect(session.external_data['idempotency_key']).not_to match(/random|SecureRandom/)
      expect(session.external_data['idempotency_key']).to include("method-#{payment_method.id}", 'attempt-1')
    end

    # P0-7 (FR-071): Legacy 入口必须打 structured usage log（payment.legacy_flow.used）。
    it 'logs a legacy flow usage metric on every legacy cart session create' do
      order = legacy_cart_order
      logger = Rails.logger
      original_info = logger.method(:info)
      allow(logger).to receive(:info) do |*args, **kwargs, &block|
        original_info.call(*args, **kwargs, &block)
      end

      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: { payment_method_id: payment_method.prefixed_id,
                     external_data: { stripe_payment_method_id: 'pm_wallet' } },
           headers: create_session_headers(order)

      expect(response).to have_http_status(:created)
      expect(logger).to have_received(:info).with(
        hash_including(
          message: 'payment.legacy_flow.used',
          flow_type: 'legacy_cart_session_create',
          entry_point: 'express_checkout',
          payment_method_id: payment_method.prefixed_id,
          order_id: order.prefixed_id
        )
      )
    end

    it 'reuses the same active session for a duplicate create (double click / HTTP retry)' do
      order = legacy_cart_order
      headers = create_session_headers(order)

      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: headers
      first_id = JSON.parse(response.body)['id']

      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: headers
      second_id = JSON.parse(response.body)['id']

      expect(response).to have_http_status(:created)
      expect(second_id).to eq(first_id)
      expect(order.reload.payment_sessions.count).to eq(1)
    end
  end
end
