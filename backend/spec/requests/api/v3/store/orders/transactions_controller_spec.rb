# frozen_string_literal: true

# PRD-20260904-api-txn-p2-2 AC-207
require 'rails_helper'

RSpec.describe 'Order transactions (Store API, TXN-P2-2)', type: :request do
  include_context 'API v3 Store authenticated'

  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }

  def pending_standard_order(owner: user)
    order = create(:order_with_line_items, store: store, user: owner, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         payment_state: nil, completed_at: nil)
    order.reload
  end

  describe 'POST /api/v3/store/orders/:order_id/transactions' do
    it 'AC-207 starts a transaction and returns transaction + payment execution (201)' do
      order = pending_standard_order

      post "/api/v3/store/orders/#{order.prefixed_id}/transactions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig('data', 'id')).to start_with('txn_')
      expect(body.dig('data', 'attributes', 'state')).to eq('payment_pending')
      expect(body.dig('data', 'payment_execution', 'id')).to start_with('ps_')
    end

    it 'AC-207 does not expose another customer order (404)' do
      order = pending_standard_order(owner: create(:user))

      post "/api/v3/store/orders/#{order.prefixed_id}/transactions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'AC-207 rejects a terminal transaction with 409 transaction_not_payable' do
      order = pending_standard_order
      post "/api/v3/store/orders/#{order.prefixed_id}/transactions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: headers
      tx_id = JSON.parse(response.body).dig('data', 'id')
      tx = PallasTrade::CommerceTransaction.find_by_prefix_id!(tx_id)
      tx.update_column(:state, 'completed') # 终态（绕过状态机直达）

      post "/api/v3/store/orders/#{order.prefixed_id}/transactions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: headers

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('transaction_not_payable')
    end
  end
end
