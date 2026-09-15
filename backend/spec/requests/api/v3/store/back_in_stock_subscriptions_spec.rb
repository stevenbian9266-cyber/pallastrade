# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'POST /api/v3/store/products/:product_id/back_in_stock_subscriptions', type: :request do
  include_context 'API v3 Store guest'

  let(:store) { @default_store }
  let(:product) { create(:product, store: store) }
  let(:path) { "/api/v3/store/products/#{product.prefixed_id}/back_in_stock_subscriptions" }

  describe 'POST' do
    it 'creates an active subscription' do
      post path, params: { email: 'customer@example.com' }, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:email]).to eq('customer@example.com')
      expect(json_response[:status]).to eq('active')
      expect(json_response[:product_id]).to eq(product.prefixed_id)
    end

    it 'is idempotent for the same email + product' do
      post path, params: { email: 'customer@example.com' }, headers: headers
      post path, params: { email: 'customer@example.com' }, headers: headers

      expect(PallasTrade::BackInStockSubscription.for_store(store).count).to eq(1)
    end

    it 'reactivates a previously notified subscription' do
      create(:back_in_stock_subscription, store: store, product: product, email: 'customer@example.com', status: 'notified')

      post path, params: { email: 'customer@example.com' }, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:status]).to eq('active')
    end

    it 'rejects an invalid email' do
      post path, params: { email: 'nope' }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 404 for an unknown product' do
      post "/api/v3/store/products/prod_doesnotexist/back_in_stock_subscriptions", params: { email: 'a@b.com' }, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    # Batch C-2（PRD-20260915-catalog-batch-c2-sku-back-in-stock）
    it 'creates a SKU-level subscription when variant_id is given' do
      variant = product.default_variant

      post path, params: { email: 'sku@example.com', variant_id: variant.prefixed_id }, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:variant_id]).to eq(variant.prefixed_id)
      expect(PallasTrade::BackInStockSubscription.for_store(store).last.variant).to eq(variant)
    end

    it 'counts SKU subscriptions separately from the product-level one' do
      variant = product.default_variant
      other_variant = create(:variant, product: product)

      post path, params: { email: 'same@example.com' }, headers: headers
      post path, params: { email: 'same@example.com', variant_id: variant.prefixed_id }, headers: headers
      post path, params: { email: 'same@example.com', variant_id: other_variant.prefixed_id }, headers: headers

      expect(PallasTrade::BackInStockSubscription.for_store(store).count).to eq(3)
    end

    it 'returns 404 for an unknown variant' do
      post path, params: { email: 'a@b.com', variant_id: 'variant_doesnotexist' }, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when the variant belongs to another product' do
      other_variant = create(:product, store: store, name: 'Other Product').default_variant

      post path, params: { email: 'a@b.com', variant_id: other_variant.prefixed_id }, headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
