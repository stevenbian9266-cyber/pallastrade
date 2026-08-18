# frozen_string_literal: true

require 'spec_helper'

# PRD-20260818-catalog-p0-4-产品评论
# AC-002 / AC-003：approved 只读列表 + 登录客户提交 + 未登录 401 + 重复提交拒绝
RSpec.describe 'Product reviews API', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:product) { create(:product, store: store) }
  let(:path) { "/api/v3/store/products/#{product.prefixed_id}/reviews" }

  describe 'GET /api/v3/store/products/:product_id/reviews' do
    it 'returns only approved reviews' do
      approved = create(:review, store: store, product: product, user: user, rating: 4, status: 'approved')
      create(:review, store: store, product: product, user: create(:user), rating: 1, status: 'pending')
      create(:review, store: store, product: product, user: create(:user), rating: 2, status: 'rejected')

      get path, headers: headers

      expect(response).to have_http_status(:ok)
      ids = json_response.map { |r| r['id'] }
      expect(ids).to eq([approved.prefixed_id])
      expect(json_response.first['rating']).to eq(4)
    end

    it 'returns 404 for an unknown product' do
      get "/api/v3/store/products/prod_doesnotexist/reviews", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v3/store/products/:product_id/reviews' do
    it 'creates a pending review for an authenticated customer' do
      post path, params: { rating: 5, title: 'Love it', body: 'Works great' }, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:rating]).to eq(5)
      expect(json_response[:title]).to eq('Love it')
      review = PallasTrade::Review.for_store(store).last
      expect(review.status).to eq('pending')
      expect(review.user).to eq(user)
    end

    it 'rejects unauthenticated submission with 401' do
      guest_headers = api_key_headers
      post path, params: { rating: 5, title: 'x', body: 'y' }, headers: guest_headers
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a duplicate review from the same customer' do
      create(:review, store: store, product: product, user: user)

      post path, params: { rating: 3, title: 'Again', body: 'Second try' }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'flags verified purchase when the customer completed an order for the product' do
      create(:completed_order_with_totals, store: store, user: user, variants: [product.default_variant])

      post path, params: { rating: 5, title: 'Verified', body: 'Bought it' }, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:verified_purchase]).to be(true)
    end

    it 'returns 404 for an unknown product' do
      post "/api/v3/store/products/prod_doesnotexist/reviews", params: { rating: 5 }, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
