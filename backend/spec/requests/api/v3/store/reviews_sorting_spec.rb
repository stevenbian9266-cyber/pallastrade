# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-batch-f4-review-sorting AC-001 AC-002 AC-003 AC-004 AC-005 AC-008 AC-009 AC-010
#   AC-008: the response stays an additive superset (F-1 meta keys + sort), which is what the
#           contract-drift gate (`harness generated:check`) protects in CI.
RSpec.describe 'Store review sorting', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:product) { create(:product, store: store) }
  let(:path) { "/api/v3/store/products/#{product.prefixed_id}/reviews" }

  # Ratings deliberately repeat so the tie-break (id DESC) is exercised.
  let!(:reviews) do
    [5, 3, 4, 5, 1].each_with_index.map do |rating, index|
      create(
        :review, store: store, product: product, user: create(:user),
                 rating: rating, title: "T#{index}", body: 'B', status: 'approved',
                 created_at: Time.current - index.minutes
      )
    end
  end

  def ratings_in(body)
    body['data'].map { |review| review['rating'] }
  end

  it 'falls back to the default ordering for an unknown or blank sort (AC-001)' do
    get path, params: { sort: 'banana' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(json_response['meta']['sort']).to eq('newest')

    get path, params: { sort: '' }, headers: headers
    expect(json_response['meta']['sort']).to eq('newest')

    get path, headers: headers
    expect(json_response['meta']['sort']).to eq('newest')
  end

  it 'orders by rating desc and pages without repeats or gaps (AC-002 / AC-010)' do
    get path, params: { sort: 'highest_rating', limit: 2 }, headers: headers

    expect(json_response['meta']['sort']).to eq('highest_rating')
    expect(ratings_in(json_response)).to eq([5, 5])

    collected = []
    (1..3).each do |page|
      get path, params: { sort: 'highest_rating', limit: 2, page: page }, headers: headers
      collected.concat(json_response['data'].map { |review| review['id'] })
    end

    expect(collected.size).to eq(5)
    expect(collected.uniq.size).to eq(5)
    expect(collected).to match_array(reviews.map(&:prefixed_id))
  end

  it 'orders by rating asc (AC-003)' do
    get path, params: { sort: 'lowest_rating' }, headers: headers

    expect(ratings_in(json_response)).to eq([1, 3, 4, 5, 5])
  end

  it 'echoes the applied sort without dropping the F-1 meta keys (AC-004)' do
    get path, params: { sort: 'highest_rating' }, headers: headers

    meta = json_response['meta']
    expect(meta.keys).to include(
      'page', 'limit', 'count', 'pages', 'from', 'to', 'in',
      'previous', 'next', 'rating_distribution', 'sort'
    )
    expect(meta['sort']).to eq('highest_rating')
  end

  it 'keeps the distribution independent of the ordering and of the page (AC-005)' do
    expect(PallasTrade::Review.approved.where(product_id: product.id).count).to eq(5)
    create(:review, store: store, product: product, user: create(:user), rating: 1, status: 'pending')

    expected = { '1' => 1, '2' => 0, '3' => 1, '4' => 1, '5' => 2 }

    %w[newest highest_rating lowest_rating].each do |sort|
      get path, params: { sort: sort, limit: 2 }, headers: headers
      expect(json_response['meta']['rating_distribution']).to eq(expected)
      expect(json_response['data'].size).to eq(2)
    end
  end

  it 'keeps the pre-F-4 ordering when sort is omitted (AC-009)' do
    get path, headers: headers
    newest_first = json_response['data'].map { |review| review['id'] }

    expected = reviews.sort_by { |review| [-review.created_at.to_f, -review.id] }.map(&:prefixed_id)
    expect(newest_first).to eq(expected)
  end
end
