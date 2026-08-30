# frozen_string_literal: true

require 'spec_helper'

# PRD-20260829-checkout-订单流程标准电商改造 AC-001/AC-002/AC-003/AC-005（购物车 API + submit）
RSpec.describe 'Store Carts API (standard flow)', type: :request do
  include_context 'API v3 Store guest'

  let(:store) { @default_store || create(:store, default: true) }
  let(:product) { create(:product_in_stock, store: store) }
  let(:variant) { product.master }
  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en') }

  before do
    variant.set_price('USD', 19.99) unless variant.amount_in('USD')
    shipping_category = create(:shipping_category)
    product.update!(shipping_category_id: shipping_category.id)
    # zone 覆盖 US（address 默认国家）→ 生成运费
    zone = create(:zone)
    us = PallasTrade::Country.find_by(iso: 'US') || create(:country, iso: 'US', name: 'United States')
    zone.members << PallasTrade::ZoneMember.create(zoneable: us)
    create(:shipping_method, zones: [zone], shipping_categories: [shipping_category])
  end

  describe 'POST /api/v3/store/carts' do
    it 'creates a cart and returns the new ShoppingCart shape (cart_ prefix)' do
      post '/api/v3/store/carts', params: {}, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:id]).to start_with('cart_')
      expect(json_response[:status]).to eq('active')
      expect(json_response[:currency]).to eq('USD')
      expect(json_response[:items]).to eq([])
    end
  end

  describe 'GET /api/v3/store/carts/:id (payment methods)' do
    # PRD-20260830-checkout AC-001：统一下单页需要购物车级可用支付方式
    it 'returns active front-end payment methods scoped to the store' do
      create(:bogus_payment_method, name: 'Card', store: store, active: true, display_on: 'both')

      get "/api/v3/store/carts/#{cart.prefixed_id}", params: {}, headers: headers.merge('x-pallastrade-token' => cart.token)

      expect(response).to have_http_status(:ok)
      expect(json_response[:id]).to eq(cart.prefixed_id)
      methods = json_response[:payment_methods]
      expect(methods).to be_present
      expect(methods.map { |m| m[:id] }).to all(start_with('pm_'))
      expect(methods.map { |m| m[:name] }).to include('Card')
    end
  end

  describe 'cart item lifecycle' do
    it 'adds / lists / updates / deletes items' do
      token_headers = headers.merge('x-pallastrade-token' => cart.token)

      # add
      post "/api/v3/store/carts/#{cart.prefixed_id}/items",
           params: { variant_id: variant.prefixed_id, quantity: 2, selected: true }, headers: token_headers
      expect(response).to have_http_status(:created)
      item_id = json_response[:items].first[:id]
      expect(json_response[:item_total]).to eq('39.98')

      # update quantity + selection
      patch "/api/v3/store/carts/#{cart.prefixed_id}/items/#{item_id}",
            params: { quantity: 3, selected: false }, headers: token_headers
      expect(response).to have_http_status(:ok)
      item = json_response[:items].first
      expect(item[:quantity]).to eq(3)
      expect(item[:selected]).to be(false)

      # delete
      delete "/api/v3/store/carts/#{cart.prefixed_id}/items/#{item_id}", headers: token_headers
      expect(response).to have_http_status(:ok)
      expect(json_response[:items]).to be_empty
    end

    it 'rejects an item for a variant outside the store' do
      other_store = create(:store, code: "spec_#{SecureRandom.hex(4)}")
      alien = create(:variant, product: create(:product, store: other_store))

      post "/api/v3/store/carts/#{cart.prefixed_id}/items",
           params: { variant_id: alien.prefixed_id, quantity: 1 }, headers: headers.merge('x-pallastrade-token' => cart.token)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v3/store/carts/:id (update shipping method)' do
    it 'assigns the shipping method by prefixed id (dm_)' do
      shipping_method = PallasTrade::ShippingMethod.first
      token_headers = headers.merge('x-pallastrade-token' => cart.token)

      patch "/api/v3/store/carts/#{cart.prefixed_id}",
            params: { shipping_method_id: shipping_method.prefixed_id }, headers: token_headers

      expect(response).to have_http_status(:ok)
      cart.reload
      expect(cart.shipping_method).to eq(shipping_method)
      # 序列化结果回显 dm_ 前缀
      expect(json_response[:shipping_method_id]).to eq(shipping_method.prefixed_id)
    end

    it 'returns 404 for an unknown shipping method' do
      token_headers = headers.merge('x-pallastrade-token' => cart.token)

      patch "/api/v3/store/carts/#{cart.prefixed_id}",
            params: { shipping_method_id: 'dm_doesnotexist' }, headers: token_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v3/store/carts/:id/submit' do
    it 'creates a pending order and converts the cart' do
      cart.update!(shipping_address: create(:address, user: nil), email: 'buyer@example.com')
      cart.cart_items.create!(variant: variant, quantity: 2, selected: true)

      post "/api/v3/store/carts/#{cart.prefixed_id}/submit", headers: headers.merge('x-pallastrade-token' => cart.token)

      expect(response).to have_http_status(:ok)
      order = json_response
      expect(order[:id]).to start_with('or_')
      expect(order[:state]).to eq('pending')
      expect(order[:status]).to eq('placed')
      expect(order[:submitted_at]).to be_present
      expect(order[:cart_id]).to eq(cart.prefixed_id)
      expect(order[:items].length).to eq(1)

      cart.reload
      expect(cart.status).to eq('converted')
    end

    it 'fails when no item is selected' do
      cart.update!(shipping_address: create(:address, user: nil))
      cart.cart_items.create!(variant: variant, quantity: 1, selected: false)

      post "/api/v3/store/carts/#{cart.prefixed_id}/submit", headers: headers.merge('x-pallastrade-token' => cart.token)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'GET /api/v3/store/orders/:id (checkout read)' do
    it 'exposes a pending standard-flow order to its token holder' do
      cart.update!(shipping_address: create(:address, user: nil), email: 'buyer@example.com')
      cart.cart_items.create!(variant: variant, quantity: 1, selected: true)
      post "/api/v3/store/carts/#{cart.prefixed_id}/submit", headers: headers.merge('x-pallastrade-token' => cart.token)
      expect(response).to have_http_status(:ok)
      order_id = json_response[:id]

      get "/api/v3/store/orders/#{order_id}", headers: headers.merge('x-pallastrade-token' => cart.token)

      expect(response).to have_http_status(:ok)
      expect(json_response[:id]).to eq(order_id)
      expect(json_response[:state]).to eq('pending')
    end

    # PRD-20260829-checkout 订单模块 AC-001：账户页勾选 1 笔「已完成但未支付」订单
    # （completed_at 已设、payment_state=balance_due）→ 跳转单订单 checkout 纯支付页。
    # show 必须使用 :show 能力（P1 曾误用 :update，导致已完成订单 403）。
    it 'exposes a completed-but-unpaid order to its token holder (single-order checkout)' do
      cart.update!(shipping_address: create(:address, user: nil), email: 'buyer@example.com')
      cart.cart_items.create!(variant: variant, quantity: 1, selected: true)
      post "/api/v3/store/carts/#{cart.prefixed_id}/submit", headers: headers.merge('x-pallastrade-token' => cart.token)
      expect(response).to have_http_status(:ok)
      order_id = json_response[:id]

      order = PallasTrade::Order.find_by_prefix_id!(order_id)
      # 模拟 legacy/已完成未支付订单：completed_at 已设但金额未结清
      order.update_columns(completed_at: Time.current, state: 'complete', payment_state: 'balance_due')

      get "/api/v3/store/orders/#{order_id}", headers: headers.merge('x-pallastrade-token' => cart.token)

      expect(response).to have_http_status(:ok)
      expect(json_response[:id]).to eq(order_id)
      expect(json_response[:payment_status]).to eq('balance_due')
    end
  end
end
