# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-batch-f2-stock-shipping AC-003 / AC-004 / AC-005 / AC-011 / AC-013 / AC-014
#   AC-004：分桶不得放大查询（以列表为断言载体：1 条 vs 6 条差值 ≤ 2）
#   AC-011：只增字段（响应是既有键的超集）+ generated:check 无漂移（CI 门禁，见 PRD §9）
# 另：AC-004（列表查询数不随条数增长，见 product list 第二例）
#     AC-011（只增不改：既有布尔字段仍是超集的一部分）
RSpec.describe 'Store API stock status & shipping', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:product) { create(:product, store: store, status: 'active') }

  # Counts real (non-cached, non-schema) queries inside the block.
  def count_queries
    count = 0
    counter = lambda do |*, payload|
      count += 1 unless payload[:cached] || payload[:name] == 'SCHEMA'
    end

    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }
    count
  end

  describe 'product detail (AC-003)' do
    it 'exposes a bucketed stock_status and never an exact quantity' do
      product.master.stock_items.update_all(count_on_hand: 2, backorderable: false)

      get "/api/v3/store/products/#{product.prefixed_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('stock_status')
      expect(response.body).to include('low_stock')
      expect(response.body).not_to include('count_on_hand')
      expect(response.body).not_to include('total_on_hand')
    end
  end

  describe 'product list (AC-013 / AC-014)' do
    it 'carries the same bucket as the detail endpoint' do
      product.master.stock_items.update_all(count_on_hand: 1, backorderable: false)

      get '/api/v3/store/products', headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('low_stock')

      get "/api/v3/store/products/#{product.prefixed_id}", headers: headers
      expect(response.body).to include('low_stock')
    end

    it 'does not leak quantities and does not scale queries with page size' do
      create_list(:product, 5, store: store, status: 'active')

      single = count_queries do
        get '/api/v3/store/products', params: { limit: 1 }, headers: headers
      end
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('count_on_hand')

      many = count_queries do
        get '/api/v3/store/products', params: { limit: 6 }, headers: headers
      end

      # Serializing the bucket must not add a query per product.
      expect(many - single).to be <= 2
    end

    it 'adds the bucket without dropping the booleans 4.2 shipped (AC-011)' do
      # The list must actually carry a product, otherwise the assertion would
      # pass vacuously against an empty envelope.
      product.master.stock_items.update_all(count_on_hand: 1, backorderable: false)
      create_list(:product, 2, store: store, status: 'active')

      get '/api/v3/store/products', headers: headers

      body = response.body
      expect(body).to include('low_stock')
      %w[purchasable in_stock backorderable stock_status].each do |key|
        expect(body).to include(key)
      end
    end
  end

  describe 'delivery methods (AC-005)' do
    let(:shipping_category) { PallasTrade::ShippingCategory.create!(name: 'Default') }

    before do
      PallasTrade::ShippingMethod.create!(
        name: 'Standard',
        display_on: 'both',
        estimated_transit_business_days_min: 3,
        estimated_transit_business_days_max: 5,
        shipping_categories: [shipping_category],
        calculator: PallasTrade::Calculator::Shipping::FlatRate.new(preferred_amount: 5)
      )
    end

    it 'publishes the transit window' do
      get '/api/v3/store/shipping_methods', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('estimated_transit_business_days_min')
      expect(response.body).to include('estimated_transit_business_days_max')
    end

    it 'answers the PDP estimate endpoint' do
      store.preferred_free_shipping_threshold = 75
      store.save!

      get '/api/v3/store/shipping_estimate',
          params: { product_id: product.prefixed_id, country: 'US' }, headers: headers

      expect(response).to have_http_status(:ok)
      data = json_response['data']
      expect(data['available']).to be true
      expect(data['min_days']).to eq(3)
      expect(data['max_days']).to eq(5)
      expect(data['free_shipping_threshold'].to_d).to eq(75.to_d)
      expect(data['business_day_source']).to eq('weekdays')
    end

    it 'still answers without a product id' do
      get '/api/v3/store/shipping_estimate', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['available']).to be true
    end
  end
end
