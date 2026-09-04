# frozen_string_literal: true

# PRD-20260904-api-txn-p2-2 AC-207（Resume 读模型 owner 作用域）
require 'rails_helper'

RSpec.describe 'Store transactions resume (TXN-P2-2)', type: :request do
  include_context 'API v3 Store authenticated'

  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }
  let(:order) do
    o = create(:order_with_line_items, store: store, user: user, shipment_cost: 0)
    o.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                     payment_state: nil, completed_at: nil)
    o.reload
  end

  describe 'GET /api/v3/store/transactions/:id' do
    it 'returns the resume read model for an owned transaction' do
      post "/api/v3/store/orders/#{order.prefixed_id}/transactions",
           params: { payment_method_id: payment_method.prefixed_id },
           headers: headers
      tx_id = JSON.parse(response.body).dig('data', 'id')

      get "/api/v3/store/transactions/#{tx_id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig('data', 'id')).to eq(tx_id)
      expect(body.dig('data', 'state')).to eq('payment_pending')
      expect(body.dig('data', 'participants', 0, 'role')).to eq('primary')
      expect(body.dig('data', 'payment_sessions', 0, 'id')).to start_with('ps_')
    end

    it 'hides another customer transaction (404)' do
      other = create(:user)
      other_order = create(:order_with_line_items, store: store, user: other, shipment_cost: 0)
      other_order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                                 payment_state: nil, completed_at: nil)
      result = PallasTrade::Transactions::Start.call(
        order: other_order, payment_method: payment_method, purpose: 'purchase'
      )
      tx_id = result.value[:transaction].prefixed_id

      get "/api/v3/store/transactions/#{tx_id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
