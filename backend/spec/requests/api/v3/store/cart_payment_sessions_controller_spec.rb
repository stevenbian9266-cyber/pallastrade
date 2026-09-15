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

    # PRD-20260915-checkout-checkout-收尾收敛-b5-legacy-端点治理-usage-metric-收口与零新增调用守护 AC-002
    # B5 FR-002：六类 legacy 路由的统一字段契约（身份 / 动作 / 弃用 / successor）。
    it 'carries the unified legacy metric contract fields' do
      order = legacy_cart_order
      logger = Rails.logger
      original_info = logger.method(:info)
      allow(logger).to receive(:info) do |*args, **kwargs, &block|
        original_info.call(*args, **kwargs, &block)
      end

      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: create_session_headers(order)

      expect(response).to have_http_status(:created)
      expect(logger).to have_received(:info).with(
        hash_including(
          requested_cart_id: order.prefixed_id,
          legacy_identity: 'order_table_cart',
          action: 'create',
          deprecated: true,
          canonical_successor: '/api/v3/store/orders/:order_id/payment_sessions'
        )
      )
    end

    # PRD-20260915-checkout-checkout-收尾收敛-b5-legacy-端点治理-usage-metric-收口与零新增调用守护 AC-004
    # B5 FR-004：legacy 身份请求带机器可读弃用信号（Deprecation / Warning / Link）。
    it 'marks legacy traffic with machine-readable deprecation headers' do
      order = legacy_cart_order

      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: create_session_headers(order)

      expect(response).to have_http_status(:created)
      expect(response.headers['Deprecation']).to eq('true')
      expect(response.headers['Warning']).to include('299')
      expect(response.headers['Link']).to eq('</api/v3/store/orders/:order_id/payment_sessions>; rel="successor-version"')
    end

    # PRD-20260915-checkout-checkout-收尾收敛-b5-legacy-端点治理-usage-metric-收口与零新增调用守护 AC-008
    # B5 FR-008：§45 matrix 六行均声明 canonical successor（防“声明缺口”回归）。
    it 'declares a canonical successor on every legacy cart controller' do
      api_root = 'pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/carts'
      controllers = %w[
        payment_sessions_controller.rb payments_controller.rb fulfillments_controller.rb
        discount_codes_controller.rb gift_cards_controller.rb store_credits_controller.rb
      ]

      controllers.each do |file|
        source = File.read(Rails.root.join(api_root, file))
        expect(source).to include('def legacy_canonical_successor'), "#{file} 未声明 canonical successor"
      end

      observable = File.read(
        Rails.root.join('pallastrade_gems/pallastrade_api/app/controllers/concerns/pallastrade/api/v3/legacy_flow_observable.rb')
      )
      expect(observable).to include("Deprecation").and include("successor-version")
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
