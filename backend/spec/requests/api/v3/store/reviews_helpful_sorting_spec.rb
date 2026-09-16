# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-batch-f5-helpful-vote AC-009 AC-010
#
#   AC-009 ← FR-005：most_helpful 按票数降序 + 唯一 tie-break（翻页不重不漏）；
#                    meta.sort 回显；rating_distribution 与排序正交
#   AC-010 ← FR-005：未知/空 sort 仍回退 newest（F-4 契约不回归）
RSpec.describe 'Store review most_helpful sorting', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:product) { create(:product, store: store) }
  let(:path) { "/api/v3/store/products/#{product.prefixed_id}/reviews" }

  # Five approved reviews; vote counts deliberately repeat (1 / 1 / 0) so the
  # `id DESC` tie-break is exercised by both the ranked and the unranked part.
  let!(:reviews) do
    Array.new(5) do |index|
      create(
        :review, store: store, product: product, user: create(:user),
                 rating: 5, title: "T#{index}", body: 'B', status: 'approved',
                 created_at: Time.current - index.minutes
      )
    end
  end

  before do
    2.times { create(:review_vote, review: reviews[0], user: create(:user), store: store) }
    create(:review_vote, review: reviews[1], user: create(:user), store: store)
  end

  def ids_in(body)
    body['data'].map { |review| review['id'] }
  end

  it 'orders by vote count and breaks ties by id desc (AC-009)' do
    get path, params: { sort: 'most_helpful' }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(json_response['meta']['sort']).to eq('most_helpful')
    expect(ids_in(json_response)).to eq(
      [reviews[0], reviews[1], reviews[4], reviews[3], reviews[2]].map(&:prefixed_id)
    )
    expect(json_response['data'].map { |review| review['helpful_votes_count'] })
      .to eq([2, 1, 0, 0, 0])
  end

  it 'pages without repeats or gaps (AC-009)' do
    collected = []
    (1..3).each do |page|
      get path, params: { sort: 'most_helpful', limit: 2, page: page }, headers: headers
      collected.concat(ids_in(json_response))
    end

    expect(collected.size).to eq(5)
    expect(collected.uniq.size).to eq(5)
    expect(collected).to match_array(reviews.map(&:prefixed_id))
  end

  it 'keeps the rating distribution orthogonal to the ordering (AC-009)' do
    get path, params: { sort: 'most_helpful' }, headers: headers
    most_helpful_distribution = json_response['meta']['rating_distribution']

    get path, params: { sort: 'lowest_rating' }, headers: headers

    expect(json_response['meta']['rating_distribution']).to eq(most_helpful_distribution)
    expect(json_response['meta']['rating_distribution'].values.sum).to eq(5)
  end

  it 'still falls back to the default for an unknown sort (AC-010)' do
    get path, params: { sort: 'banana' }, headers: headers
    expect(json_response['meta']['sort']).to eq('newest')

    get path, params: { sort: '' }, headers: headers
    expect(json_response['meta']['sort']).to eq('newest')
  end

  it 'keeps newest as the default ordering (AC-010)' do
    get path, headers: headers

    expect(json_response['meta']['sort']).to eq('newest')
    expect(ids_in(json_response)).to eq(reviews.map(&:prefixed_id))
  end
end
