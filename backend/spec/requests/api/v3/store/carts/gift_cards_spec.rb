# frozen_string_literal: true

require 'spec_helper'

# PRD-20260914-checkout-cart-gift-cards-canonical AC-001/AC-002/AC-003/AC-005/AC-006：
# `cart_` 前缀购物车不再 404（双解析），礼品卡意图读写 `private_metadata`。
RSpec.describe 'Store Cart gift cards API (canonical cart_)', type: :request do
  include_context 'API v3 Store guest'

  let(:store) { @default_store || create(:store, default: true) }
  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en') }
  let(:cart_headers) { headers.merge('x-pallastrade-token' => cart.token) }
  let(:gift_card) { create(:gift_card, store: store, amount: 25.00) }

  describe 'POST /api/v3/store/carts/:cart_id/gift_cards' do
    # AC-001 / AC-005：修复前此请求 → 404 cart_not_found（legacy 解析器解析不到 pallastrade_carts）
    it 'applies a valid gift card onto a cart_ shopping cart' do
      post "/api/v3/store/carts/#{cart.prefixed_id}/gift_cards",
           params: { code: gift_card.code }, headers: cart_headers

      expect(response).to have_http_status(:created)
      expect(json_response[:id]).to eq(cart.prefixed_id)
      expect(cart.reload.private_metadata['gift_card_code']).to eq(gift_card.code.downcase)
      # AC-005：载荷暴露意图（code + 余额展示），供 UI 展示「已应用」
      expect(json_response[:gift_card][:code]).to eq(gift_card.code)
      expect(json_response[:gift_card][:display_amount_remaining]).to be_present
    end

    # AC-002：错误码与 legacy 端点一致
    it 'rejects an unknown code with 404 gift_card_not_found' do
      post "/api/v3/store/carts/#{cart.prefixed_id}/gift_cards",
           params: { code: 'NOPE' }, headers: cart_headers

      expect(response).to have_http_status(:not_found)
      expect(json_response[:error][:code]).to eq('gift_card_not_found')
      expect(cart.reload.private_metadata['gift_card_code']).to be_nil
    end

    # AC-002
    it 'rejects expired and redeemed cards with the legacy error codes' do
      expired = create(:gift_card, :expired, store: store)
      redeemed = create(:gift_card, :redeemed, store: store)

      post "/api/v3/store/carts/#{cart.prefixed_id}/gift_cards",
           params: { code: expired.code }, headers: cart_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('gift_card_expired')

      post "/api/v3/store/carts/#{cart.prefixed_id}/gift_cards",
           params: { code: redeemed.code }, headers: cart_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('gift_card_already_redeemed')
    end
  end

  describe 'DELETE /api/v3/store/carts/:cart_id/gift_cards/:id' do
    before { cart.update!(private_metadata: { 'gift_card_code' => gift_card.code.downcase }) }

    # AC-003
    it 'removes the stored gift card intent' do
      delete "/api/v3/store/carts/#{cart.prefixed_id}/gift_cards/#{gift_card.code}",
             headers: cart_headers

      expect(response).to have_http_status(:ok)
      expect(cart.reload.private_metadata['gift_card_code']).to be_nil
    end

    # AC-003：幂等
    it 'is idempotent' do
      2.times do
        delete "/api/v3/store/carts/#{cart.prefixed_id}/gift_cards/#{gift_card.code}",
               headers: cart_headers
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # AC-006：非 `cart_` id 仍走 legacy 解析（行为不变）+ 收敛观测标记
  describe 'legacy resolution' do
    it 'routes non-cart_ ids to the legacy resolver and logs the observation marker' do
      allow(Rails.logger).to receive(:info).and_call_original

      post '/api/v3/store/carts/or_nonexistent/gift_cards',
           params: { code: 'SAVE10' }, headers: headers

      expect(Rails.logger).to have_received(:info).with(
        hash_including(message: '[legacy-gift-cards] legacy cart resolution used', flow_type: 'legacy_cart_gift_cards')
      )
      expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
    end

    # PRD-20260915-checkout-checkout-收尾收敛-b5-legacy-端点治理-usage-metric-收口与零新增调用守护 AC-002 AC-004
    # B5 FR-002/FR-004：统一字段（身份/动作/弃用/successor）+ 机器可读弃用头。
    it 'logs the unified contract and marks the response as deprecated for legacy ids' do
      allow(Rails.logger).to receive(:info).and_call_original

      post '/api/v3/store/carts/or_nonexistent/gift_cards',
           params: { code: 'SAVE10' }, headers: headers

      expect(Rails.logger).to have_received(:info).with(
        hash_including(
          message: '[legacy-gift-cards] legacy cart resolution used',
          flow_type: 'legacy_cart_gift_cards',
          requested_cart_id: 'or_nonexistent',
          legacy_identity: 'order_table_cart',
          action: 'create',
          deprecated: true,
          canonical_successor: '/api/v3/store/carts'
        )
      )
      expect(response.headers['Deprecation']).to eq('true')
      expect(response.headers['Warning']).to include('299')
      expect(response.headers['Link']).to eq('</api/v3/store/carts>; rel="successor-version"')
    end

    # PRD-20260915-checkout-checkout-收尾收敛-b5-legacy-端点治理-usage-metric-收口与零新增调用守护 AC-005
    # B5 FR-004/S1：`cart_` canonical 流量不得被标弃用、不得计入 legacy 度量。
    it 'never marks canonical cart_ traffic as deprecated' do
      allow(Rails.logger).to receive(:info).and_call_original

      post "/api/v3/store/carts/#{cart.prefixed_id}/gift_cards",
           params: { code: gift_card.code }, headers: cart_headers

      expect(response).to have_http_status(:created)
      expect(response.headers['Deprecation']).to be_nil
      expect(response.headers['Warning']).to be_nil
      expect(response.headers['Link']).to be_nil
      expect(Rails.logger).not_to have_received(:info).with(
        hash_including(message: '[legacy-gift-cards] legacy cart resolution used')
      )
    end
  end
end
