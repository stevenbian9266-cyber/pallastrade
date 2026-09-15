# frozen_string_literal: true

require 'spec_helper'

# PRD-20260914-checkout-cart-discount-codes-canonical AC-001/AC-002/AC-003：
# `cart_` 前缀的购物车不再 403（双解析），应用/移除优惠码写读 `private_metadata`。
RSpec.describe 'Store Cart discount codes API (canonical cart_)', type: :request do
  include_context 'API v3 Store guest'

  let(:store) { @default_store || create(:store, default: true) }
  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en') }
  let(:cart_headers) { headers.merge('x-pallastrade-token' => cart.token) }

  before do
    create(:promotion_with_order_adjustment, store: store, code: 'SAVE10',
                                             weighted_order_adjustment_amount: 10)
  end

  describe 'POST /api/v3/store/carts/:cart_id/discount_codes' do
    # AC-001：修复前此请求 → 403 access_denied（legacy 解析器解析不到 pallastrade_carts）
    it 'applies a valid code onto a cart_ shopping cart' do
      post "/api/v3/store/carts/#{cart.prefixed_id}/discount_codes",
           params: { code: 'SAVE10' }, headers: cart_headers

      expect(response).to have_http_status(:created)
      expect(json_response[:id]).to eq(cart.prefixed_id)
      expect(cart.reload.private_metadata['discount_code']).to eq('save10')
      # PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-009：
      # 车阶段优惠码意图需对外可读（购物车页「已应用」行），金额到提交时才算。
      expect(json_response[:discount_code]).to eq('save10')
    end

    # PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-009：
    # 三种抵扣意图未应用时字段均为 null → 前端据此不渲染对应行。
    it 'reports null credit intents on a bare cart_' do
      get "/api/v3/store/carts/#{cart.prefixed_id}", headers: cart_headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:discount_code]).to be_nil
      expect(json_response[:gift_card]).to be_nil
      expect(json_response[:store_credit]).to be_nil
    end

    # AC-002：码大小写 / 空白不敏感，规范化后存储
    it 'normalizes the code before storing it' do
      post "/api/v3/store/carts/#{cart.prefixed_id}/discount_codes",
           params: { code: '  Save10  ' }, headers: cart_headers

      expect(response).to have_http_status(:created)
      expect(cart.reload.private_metadata['discount_code']).to eq('save10')
    end

    # AC-003：未知码 → 结构化错误码，且不落库
    it 'rejects an unknown code with coupon_code_not_found' do
      post "/api/v3/store/carts/#{cart.prefixed_id}/discount_codes",
           params: { code: 'NOPE' }, headers: cart_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('coupon_code_not_found')
      expect(cart.reload.private_metadata['discount_code']).to be_nil
    end

    # AC-002：码存在但已过期 → coupon_code_expired
    it 'rejects an expired promotion with coupon_code_expired' do
      create(:promotion_with_order_adjustment, store: store, code: 'OLD5',
                                               weighted_order_adjustment_amount: 5,
                                               starts_at: 2.days.ago, expires_at: 1.day.ago)

      post "/api/v3/store/carts/#{cart.prefixed_id}/discount_codes",
           params: { code: 'OLD5' }, headers: cart_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('coupon_code_expired')
    end
  end

  # PRD-20260914-checkout-cart-discount-codes-canonical AC-006：
  # 非 `cart_` id 仍走 legacy 解析（行为不变），且留下收敛观测标记。
  describe 'legacy resolution' do
    it 'routes non-cart_ ids to the legacy resolver and logs the observation marker' do
      allow(Rails.logger).to receive(:info).and_call_original

      post '/api/v3/store/carts/or_nonexistent/discount_codes',
           params: { code: 'SAVE10' }, headers: headers

      expect(Rails.logger).to have_received(:info).with(
        hash_including(message: '[legacy-discount-codes] legacy cart resolution used', flow_type: 'legacy_cart_discount_codes')
      )
      expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
    end
  end

  describe 'DELETE /api/v3/store/carts/:cart_id/discount_codes/:id' do
    before { cart.update!(private_metadata: { 'discount_code' => 'save10' }) }

    it 'removes the stored code' do
      delete "/api/v3/store/carts/#{cart.prefixed_id}/discount_codes/save10", headers: cart_headers

      expect(response).to have_http_status(:ok)
      expect(cart.reload.private_metadata['discount_code']).to be_nil
    end

    # AC-003：移除端点幂等（重复调用仍 200）
    it 'is idempotent' do
      2.times do
        delete "/api/v3/store/carts/#{cart.prefixed_id}/discount_codes/save10", headers: cart_headers
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
