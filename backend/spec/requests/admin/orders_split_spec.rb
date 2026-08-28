# frozen_string_literal: true

require 'spec_helper'

# PRD-20260828-admin-p6 AC-007~009：Admin 手动拆单 UI（入口 / 拆分页 / 父子树，flag 灰度）
RSpec.describe '/admin/orders/:id/split', type: :request do
  stub_authorization!

  let(:store) { @default_store }
  let(:order) { create(:order_ready_to_ship, store: store, line_items_count: 2, line_items_price: 10, shipment_cost: 0) }

  describe 'flag gating (AC-007)' do
    it 'hides the split entry when disabled (default)' do
      get "/admin/orders/#{order.prefixed_id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Split Order')
    end

    it 'redirects back to the order when the split page is opened while disabled' do
      get "/admin/orders/#{order.prefixed_id}/split"
      expect(response).to redirect_to("/admin/orders/#{order.prefixed_id}")
    end
  end

  describe 'with flag enabled' do
    before { store.update!(preferred_manual_split_enabled: true) }

    it 'AC-007 shows the split entry on the order page' do
      get "/admin/orders/#{order.prefixed_id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Split Order')
    end

    it 'AC-007 renders the split page with line item checkboxes' do
      get "/admin/orders/#{order.prefixed_id}/split"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('line_item_ids')
      expect(response.body).to include('Confirm Split')
    end

    it 'AC-008 splits line items and redirects to the parent order' do
      li_id = order.line_items.first.prefixed_id

      post "/admin/orders/#{order.prefixed_id}/split", params: { line_item_ids: [li_id] }

      expect(response).to redirect_to("/admin/orders/#{order.prefixed_id}")
      child = order.reload.children.first
      expect(child).to be_present
      expect(child.line_items.map(&:prefixed_id)).to contain_exactly(li_id)
      expect(order.reload.line_items.size).to eq(1)
    end

    it 'AC-009 renders the parent child tree on the parent order page' do
      li_id = order.line_items.first.prefixed_id
      post "/admin/orders/#{order.prefixed_id}/split", params: { line_item_ids: [li_id] }
      child = order.reload.children.first

      get "/admin/orders/#{order.prefixed_id}"
      expect(response.body).to include('Child Orders')
      expect(response.body).to include(child.number)
    end

    it 'AC-009 renders the parent banner on the child order page' do
      li_id = order.line_items.first.prefixed_id
      post "/admin/orders/#{order.prefixed_id}/split", params: { line_item_ids: [li_id] }
      child = order.reload.children.first

      get "/admin/orders/#{child.prefixed_id}"
      expect(response.body).to include('Parent Order')
      expect(response.body).to include(order.number)
    end
  end
end
