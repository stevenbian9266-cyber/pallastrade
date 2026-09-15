# frozen_string_literal: true

require 'spec_helper'

# PRD-20260914-checkout-cart-store-credits-canonical AC-001/002/003/004/007/008：
# `cart_` 前缀购物车不再 404（双解析）；需要登录（余额是账户资产）；legacy 分支零行为变化 + 观测日志。
RSpec.describe 'Store Cart store credits API (canonical cart_)', type: :request do
  include_context 'API v3 Store authenticated'

  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en', user: user) }
  let(:cart_headers) { headers.merge('x-pallastrade-token' => cart.token) }

  describe 'POST /api/v3/store/carts/:cart_id/store_credits' do
    # PRD-20260914-checkout-cart-store-credits-canonical AC-001 AC-007：修复前此请求 → 404 cart_not_found
    # （legacy 解析器解析不到 pallastrade_carts）
    it 'applies a store credit amount onto a cart_ shopping cart' do
      create(:store_credit, store: store, user: user, amount: 50.0, currency: 'USD')

      post "/api/v3/store/carts/#{cart.prefixed_id}/store_credits", params: { amount: '20' }, headers: cart_headers

      expect(response).to have_http_status(:created)
      expect(cart.reload.private_metadata['store_credit_amount']).to eq('20.0')
      expect(json_response[:store_credit][:amount]).to eq('20.0')
      expect(json_response[:store_credit][:display_amount]).to be_present
      # PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-009：
      # 抵扣意图三者互斥 —— 只有余额时可读，其余两个字段为 null（前端不渲染多余行）。
      expect(json_response[:discount_code]).to be_nil
      expect(json_response[:gift_card]).to be_nil
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-003：省略金额 → 用尽可用余额
    it 'defaults to the available credit total' do
      create(:store_credit, store: store, user: user, amount: 50.0, currency: 'USD')

      post "/api/v3/store/carts/#{cart.prefixed_id}/store_credits", params: {}, headers: cart_headers

      expect(response).to have_http_status(:created)
      expect(cart.reload.private_metadata['store_credit_amount']).to eq('50.0')
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-002
    it 'rejects guests with 401' do
      api_key_only = { 'x-pallastrade-api-key' => api_key.token }

      post "/api/v3/store/carts/#{cart.prefixed_id}/store_credits", params: { amount: '10' }, headers: api_key_only

      expect(response).to have_http_status(:unauthorized)
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-002
    it 'answers store_credit_not_available when the customer has no credit' do
      other_user = create(:user)
      other_cart = store.shopping_carts.create!(currency: 'USD', locale: 'en', user: other_user)
      other_headers = headers.merge(
        'Authorization' => "Bearer #{PallasTrade::Api::V3::TestingSupport.generate_jwt(other_user)}"
      )

      post "/api/v3/store/carts/#{other_cart.prefixed_id}/store_credits", params: { amount: '10' }, headers: other_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('store_credit_not_available')
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-002
    it 'rejects invalid amounts' do
      create(:store_credit, store: store, user: user, amount: 50.0, currency: 'USD')

      post "/api/v3/store/carts/#{cart.prefixed_id}/store_credits", params: { amount: '0' }, headers: cart_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('store_credit_invalid_amount')
    end
  end

  describe 'DELETE /api/v3/store/carts/:cart_id/store_credits' do
    before do
      create(:store_credit, store: store, user: user, amount: 50.0, currency: 'USD')
      cart.update!(private_metadata: { 'store_credit_amount' => '20.0' })
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-004
    it 'removes the stored intent and is idempotent' do
      2.times do
        delete "/api/v3/store/carts/#{cart.prefixed_id}/store_credits", headers: cart_headers
        expect(response).to have_http_status(:ok)
      end

      expect(cart.reload.private_metadata['store_credit_amount']).to be_nil
    end
  end

  # PRD-20260914-checkout-cart-store-credits-canonical AC-008：非 `cart_` id 仍走 legacy 解析（行为不变）+ 收敛观测日志
  describe 'legacy resolution' do
    it 'routes non-cart_ ids to the legacy resolver and logs the usage metric' do
      allow(Rails.logger).to receive(:info).and_call_original

      post '/api/v3/store/carts/or_nonexistent/store_credits', params: { amount: '10' }, headers: headers

      expect(Rails.logger).to have_received(:info).with(
        hash_including(message: 'cart.legacy_flow.used', flow_type: 'legacy_cart_store_credits')
      )
      expect(response).to have_http_status(:not_found)
    end
  end
end
