# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-payments-d7-payment-section-express（切片1，API 通道）
#   AC-007 ← FR-005：`option_kind` 全链路传递 —— 已配置入口（含 cart legacy 通道）可建会话
#   AC-008 ← FR-005：未配置 / 声明外入口 → 门禁拒绝且**零 session 行**（客户端不可绕过）
RSpec.describe 'D7 payment option kind (Store API)', type: :request do
  include_context 'API v3 Store authenticated'

  # 离线 provider（Bogus）：`create_payment_session` 不碰网络；
  # 入口目录 stub 成「卡 + Apple Pay」，配置里两条入口齐备 → 门禁可放行 card/apple_pay。
  let(:payment_method) do
    create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true,
                                  metadata: {
                                    'optionized' => true,
                                    'options' => [
                                      { 'kind' => 'card', 'active' => true, 'position' => 1,
                                        'frontend_kind' => 'inline', 'display_name' => 'Card' },
                                      { 'kind' => 'apple_pay', 'active' => true, 'position' => 2,
                                        'frontend_kind' => 'express', 'display_name' => 'Apple Pay' }
                                    ]
                                  })
  end

  before do
    allow_any_instance_of(PallasTrade::Gateway::Bogus).to receive(:payment_option_catalog).and_return(
      [
        { 'kind' => 'card', 'frontend_kind' => 'inline', 'display_name' => 'Card' },
        { 'kind' => 'apple_pay', 'frontend_kind' => 'express', 'display_name' => 'Apple Pay' }
      ]
    )
  end

  # 声明且已配置的入口（钱包）
  let(:declared_kind) { 'apple_pay' }

  def pending_standard_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0, line_items_price: 100)
    order.update_columns(state: 'pending', payment_state: nil, completed_at: nil)
    order.reload
  end

  def legacy_cart_order
    order = create(:order_with_line_items, store: store, user: user, shipment_cost: 0, line_items_price: 100)
    order.update_columns(state: 'cart', completed_at: nil, submitted_at: nil, payment_state: nil, payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def session_payload(order, kind)
    { payment_method_id: payment_method.prefixed_id, option_kind: kind }
  end

  describe 'POST /api/v3/store/orders/:order_id/payment_sessions' do
    # AC-007：声明的入口 → 正常建会话
    it 'starts a session for a declared option kind' do
      order = pending_standard_order

      post "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions",
           params: session_payload(order, declared_kind), headers: headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['order_id']).to eq(order.prefixed_id)
    end

    # AC-008：未配置入口（apple_pay 不在该 provider 能力目录内）→ 422 结构化错误 + 零 session 行
    it 'refuses an option kind the provider does not declare without creating a session' do
      order = pending_standard_order

      expect do
        post "/api/v3/store/orders/#{order.prefixed_id}/payment_sessions",
             params: session_payload(order, 'google_pay'), headers: headers
      end.not_to change(PallasTrade::PaymentSession, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('payment_option_not_available')
    end
  end

  describe 'POST /api/v3/store/carts/:cart_id/payment_sessions (legacy 通道)' do
    # AC-007 ← FR-005：cart 通道此前**丢弃** option_kind（静默忽略）；本切片与 orders 通道对齐
    it 'forwards the option kind so a declared entry can start a session' do
      order = legacy_cart_order

      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: session_payload(order, declared_kind),
           headers: headers.merge('x-pallastrade-token' => order.token)

      expect(response).to have_http_status(:created)
    end

    # AC-008：未声明入口必须在**建会话前**被拦下（改动前 option_kind 被忽略 → 会建会话）
    it 'refuses an undeclared entry without creating a session' do
      order = legacy_cart_order

      expect do
        post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
             params: session_payload(order, 'google_pay'),
             headers: headers.merge('x-pallastrade-token' => order.token)
      end.not_to change(PallasTrade::PaymentSession, :count)

      expect(response).to have_http_status(:unprocessable_content)
      # legacy 通道沿用统一校验错误码（B5 治理：不新增支付能力、不改 legacy 契约）
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('validation_error')
    end
  end

  # FR-005 / AC-007：durable transaction 通道（前台 or_ 页实际调用路径）——
  # `orders.transactions.create` 必须能把入口一路传到 `PaymentSessions::Start`。
  describe 'POST /api/v3/store/orders/:order_id/transactions' do
    it 'starts the transaction with a declared option kind' do
      order = pending_standard_order

      post "/api/v3/store/orders/#{order.prefixed_id}/transactions",
           params: session_payload(order, declared_kind), headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['state']).to be_present
      expect(body.dig('payment_execution', 'id')).to start_with('ps_')
    end

    # AC-008：不可用入口 → 结构化错误 + 零会话（且不遗留事务副作用）
    it 'refuses an undeclared entry with a structured error and no session' do
      order = pending_standard_order

      expect do
        post "/api/v3/store/orders/#{order.prefixed_id}/transactions",
             params: session_payload(order, 'google_pay'), headers: headers
      end.not_to change(PallasTrade::PaymentSession, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('payment_option_not_available')
    end
  end
end
