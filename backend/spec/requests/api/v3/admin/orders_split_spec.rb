# frozen_string_literal: true

require 'spec_helper'

# PRD-20260828-admin-p6 AC-001~006：POST /api/v3/admin/orders/:id/split（flag 灰度）
RSpec.describe '/api/v3/admin/orders/:id/split', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
  let(:order) { create(:order_ready_to_ship, store: store, line_items_count: 3, line_items_price: 10, shipment_cost: 0) }
  let(:line_item_ids) { order.line_items.first(2).map(&:prefixed_id) }

  def post_split(params = {})
    post "/api/v3/admin/orders/#{order.prefixed_id}/split",
         params: params,
         headers: headers
  end

  describe 'flag gating' do
    it 'AC-001 returns 404 when manual split is disabled (default)' do
      post_split(groups: { manual: line_item_ids })

      expect(response).to have_http_status(:not_found)
      expect(order.reload.children).to be_empty
    end
  end

  describe 'with flag enabled' do
    before { store.update!(preferred_manual_split_enabled: true) }

    it 'AC-001 splits line items and returns parent + children' do
      post_split(groups: { manual: line_item_ids })

      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body[:data][:parent][:id]).to eq(order.prefixed_id)
      expect(body[:data][:parent][:is_parent]).to be true
      expect(body[:data][:children].size).to eq(1)
      child = body[:data][:children].first
      expect(child[:parent_id]).to eq(order.prefixed_id)
      expect(child[:is_child]).to be true

      # 子订单已补为 completed
      expect(PallasTrade::Order.find_by_prefix_id!(child[:id])).to be_completed
    end

    it 'AC-006 conserves totals (parent combined total == original total)' do
      # 父订单 serializer 的 total 为 P3 聚合值（own + Σ children），应等于原订单真实总额（item + shipment）
      original = order.item_total + order.shipments.sum(&:cost)
      post_split(groups: { manual: line_item_ids })

      body = json_response
      parent_total = body[:data][:parent][:total].to_f

      expect(parent_total.round(2)).to eq(original.round(2))
    end

    it 'AC-002 rejects an order with no line items' do
      empty = create(:order, store: store, state: 'complete', completed_at: Time.current)
      post "/api/v3/admin/orders/#{empty.prefixed_id}/split",
           params: { groups: { manual: ['li_xxx'] } },
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('order_cannot_split')
    end

    it 'AC-004 is idempotent — repeated split fails without duplicates' do
      post_split(groups: { manual: line_item_ids })
      expect(response).to have_http_status(:ok)

      post_split(groups: { manual: line_item_ids })
      expect(response).to have_http_status(:unprocessable_content)
      expect(order.reload.children.size).to eq(1)
    end

    it 'AC-005 rejects cross-store store_id' do
      other_store = create(:store, code: 'manual_split_other_store')
      post_split(groups: { manual: line_item_ids }, store_id: other_store.prefixed_id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('order_cannot_split')
      expect(json_response[:error][:message]).to include('Cross-store')
      expect(order.reload.children).to be_empty
    end

    it 'AC-005 rejects shipped line items' do
      li = order.line_items.first
      order.shipments.first.inventory_units.where(line_item: li).update_all(state: 'shipped')

      post_split(groups: { manual: [li.prefixed_id] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:message]).to include('shipped')
      expect(order.reload.children).to be_empty
    end
  end
end
