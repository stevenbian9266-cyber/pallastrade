# frozen_string_literal: true

require 'spec_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 FR-027/028/029
# 后台手动拆单：支持拆分到不同店铺（hash groups 带 store_id）
RSpec.describe '/api/v3/admin/orders/:id/split (跨店铺手动拆单)', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:order) { create(:order_with_line_items, store: store, user: user, currency: 'USD') }
  let(:extra_line_item) { create(:line_item, order: order, price: 50) }
  let(:target_store) { create(:store, code: 'admin_split_target') }

  describe 'POST /api/v3/admin/orders/:id/split' do
    it 'AC-027/029: hash groups 跨店拆分 → 子订单归属目标店铺，parent 指向原订单' do
      order
      product_b = create(:product, store: target_store)
      variant_b = create(:variant, product: product_b)
      line_item_b = create(:line_item, order: order, variant: variant_b, price: 30)

      post "/api/v3/admin/orders/#{order.prefixed_id}/split",
           params: { groups: { 'g1' => { 'line_item_ids' => [line_item_b.id], 'store_id' => target_store.prefixed_id } } },
           headers: headers

      expect(response).to have_http_status(:ok)
      data = json_response[:data]
      expect(data.length).to eq(1)
      expect(data.first[:parent_id]).to eq(order.prefixed_id)

      child = order.reload.children.first
      expect(child).not_to be_nil
      expect(child.store).to eq(target_store)
      expect(child.parent).to eq(order)
    end

    it 'AC-028: 目标店铺无该商品 → 422 split_error 明确错误，不产生子订单' do
      order
      extra_line_item

      post "/api/v3/admin/orders/#{order.prefixed_id}/split",
           params: { groups: { 'g1' => { 'line_item_ids' => [extra_line_item.id], 'store_id' => target_store.prefixed_id } } },
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('split_error')
      expect(json_response[:error][:message]).to include('目标店铺')
      expect(order.reload.children).to be_empty
    end
  end
end
