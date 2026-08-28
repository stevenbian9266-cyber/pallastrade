# frozen_string_literal: true

require 'spec_helper'

# PRD-20260828-checkout-p7 AC-005：父订单批量售后 Admin 入口（flag 灰度）
RSpec.describe '/admin/orders/:id/parent_order_returns', type: :request do
  stub_authorization!

  let(:store) { @default_store }
  let(:stock_location) { create(:stock_location, name: 'WH-Returns', active: true) }
  let(:reason) { create(:return_authorization_reason) }

  # 父订单 + 2 子订单，全部 units shipped
  let(:parent) { create(:order_ready_to_ship, store: store, line_items_count: 3, line_items_price: 10, shipment_cost: 0) }

  before do
    ids = parent.line_items.map(&:id)
    PallasTrade::Orders::ManualSplit.call(order: parent, groups: { a: [ids[0]], b: [ids[1]] })
    parent.children.each { |child| child.inventory_units.update_all(state: 'shipped') }
    parent.inventory_units.update_all(state: 'shipped')
    parent.reload
  end

  describe 'flag gating (AC-005)' do
    it 'hides the batch-returns entry when disabled (default)' do
      get "/admin/orders/#{parent.prefixed_id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Parent Order Returns')
    end

    it 'redirects back when the batch-returns page is opened while disabled' do
      get "/admin/orders/#{parent.prefixed_id}/parent_order_returns"
      expect(response).to redirect_to("/admin/orders/#{parent.prefixed_id}")
    end
  end

  describe 'with flag enabled' do
    before { store.update!(preferred_returns_parent_order_handling: true) }

    it 'AC-005 shows the batch-returns entry on the parent order page' do
      get "/admin/orders/#{parent.prefixed_id}"
      expect(response.body).to include('Parent Order Returns')
    end

    it 'AC-005 renders the batch-returns page with returnable orders and form' do
      get "/admin/orders/#{parent.prefixed_id}/parent_order_returns"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Create Return Authorizations')
      expect(response.body).to include('return_authorization_reason_id')
      expect(response.body).to include('stock_location_id')
    end

    it 'AC-005 creates RAs for the parent and all children and redirects' do
      post "/admin/orders/#{parent.prefixed_id}/parent_order_returns",
           params: { stock_location_id: stock_location.prefixed_id, return_authorization_reason_id: reason.prefixed_id }

      expect(response).to redirect_to("/admin/orders/#{parent.prefixed_id}")
      expect(PallasTrade::ReturnAuthorization.where(order_id: [parent.id, *parent.children.map(&:id)]).count).to eq(3)
    end
  end
end
