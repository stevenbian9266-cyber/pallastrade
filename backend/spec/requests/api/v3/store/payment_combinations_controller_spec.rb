# frozen_string_literal: true

require 'rails_helper'

# PRD-20260827-checkout-实施-p5 P5b 合并支付收银台（后端）
# AC-004/005：创建组合端点 + 组合会话完成
RSpec.describe 'Payment combinations (Store API)', type: :request do
  include_context 'API v3 Store authenticated'

  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }

  # 含地址/shipment、金额固化的未支付订单（复用 P4 构造：免运费 + 预计算税）
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

  describe 'POST /api/v3/store/payment_combinations' do
    it 'AC-004 creates a combination with server-side amount and a session' do
      order1 = unpaid_order
      order2 = unpaid_order

      post '/api/v3/store/payment_combinations',
           params: { order_ids: [order1.prefixed_id, order2.prefixed_id],
                     payment_method_id: payment_method.prefixed_id },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['id']).to start_with('pcom_')
      expect(body['status']).to eq('processing')
      expect(body['amount']).to eq((order1.amount_due + order2.amount_due).to_s)
      expect(body['payment_session']).to be_present
      expect(body['payment_session']['order_id']).to eq(order1.prefixed_id)
      # 成员订单可通过 expand=orders 展开
      expect(PallasTrade::PaymentCombination.find_by_prefix_id(body['id']).orders)
        .to contain_exactly(order1, order2)
    end

    it 'AC-004 rejects paid orders' do
      paid = unpaid_order
      paid.update_column(:payment_total, paid.total)

      post '/api/v3/store/payment_combinations',
           params: { order_ids: [paid.prefixed_id], payment_method_id: payment_method.prefixed_id },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'does not resolve another customer order for payment' do
      other_customer_order = unpaid_order
      other_customer_order.update!(user: create(:user))

      post '/api/v3/store/payment_combinations',
           params: { order_ids: [other_customer_order.prefixed_id],
                     payment_method_id: payment_method.prefixed_id },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig('error', 'message'))
        .to eq('Combination requires at least one order')
    end

    # PALLAS-CUSTOM (2026-08-29, bugfix): payment_method_id 可选——无购物车用户
    # 拿不到 cart 支付方式，服务端应回退到 store 默认会话类支付方式。
    it 'falls back to the store default session-based payment method when payment_method_id is omitted' do
      # 触发 lazy let(:payment_method)，否则不传 payment_method_id 时不会创建默认支付方式
      payment_method
      order1 = unpaid_order

      post '/api/v3/store/payment_combinations',
           params: { order_ids: [order1.prefixed_id] },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['payment_session']['payment_method_id']).to eq(payment_method.prefixed_id)
    end
  end

  describe 'PATCH /api/v3/store/carts/:cart_id/payment_sessions/:id/complete' do
    it 'AC-005 completes all member orders through the combination path' do
      order1 = unpaid_order
      order2 = unpaid_order
      combination = PallasTrade::Payments::PaymentCombinations::Create.call(
        store: store, customer: user, orders: [order1, order2], payment_method: payment_method
      ).value
      session = combination.payment_session

      patch "/api/v3/store/carts/#{order1.prefixed_id}/payment_sessions/#{session.prefixed_id}/complete",
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(combination.reload.status).to eq('succeeded')
      expect(combination.payments.count).to eq(1)
      expect(order1.reload).to be_completed
      expect(order2.reload).to be_completed
    end
  end
end
