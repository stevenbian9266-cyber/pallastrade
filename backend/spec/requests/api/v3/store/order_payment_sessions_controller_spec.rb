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
end
