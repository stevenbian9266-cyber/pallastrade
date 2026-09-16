# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-batch-f1-reviews —— 评论分页 + 评分分布
#
#   AC-002 ← FR-002：分页（page/limit，默认 10 / 上限 100，按 created_at desc, id desc）+ 标准 v3 meta
#   AC-003 ← FR-003：meta.rating_distribution 只算 approved，且各档之和 == meta.count
#   AC-008 ← FR-001：未审核评论的图片不出现在公共读接口
RSpec.describe 'Product reviews pagination and rating distribution', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:product) { create(:product, store: store) }
  let(:path) { "/api/v3/store/products/#{product.prefixed_id}/reviews" }

  def approved_review(rating:, minutes_ago:)
    create(:review, store: store, product: product, user: create(:user), rating: rating,
                    status: 'approved', created_at: minutes_ago.minutes.ago)
  end

  # PRD-20260916-catalog-batch-f1-reviews AC-002
  it 'paginates with the standard v3 meta keys' do
    first = approved_review(rating: 5, minutes_ago: 30)
    second = approved_review(rating: 4, minutes_ago: 20)
    third = approved_review(rating: 3, minutes_ago: 10)

    get path, params: { page: 2, limit: 2 }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(json_response['data'].map { |r| r['id'] }).to eq([first.prefixed_id])
    expect(json_response['meta']).to include(
      'page' => 2, 'limit' => 2, 'count' => 3, 'pages' => 2, 'previous' => 1, 'next' => nil
    )
    expect(json_response['data'].map { |r| r['id'] }).not_to include(third.prefixed_id, second.prefixed_id)
  end

  # PRD-20260916-catalog-batch-f1-reviews AC-002
  it 'defaults to ten per page, clamps the limit and tolerates an out-of-range page' do
    11.times { |index| approved_review(rating: 5, minutes_ago: index + 1) }

    get path, headers: headers
    expect(json_response['meta']).to include('limit' => 10, 'count' => 11, 'pages' => 2)

    get path, params: { limit: 999 }, headers: headers
    expect(json_response['meta']).to include('limit' => 100)

    get path, params: { page: 99 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(json_response['data']).to eq([])
    expect(json_response['meta']).to include('count' => 11)
  end

  # PRD-20260916-catalog-batch-f1-reviews AC-003
  it 'reports a rating distribution over approved reviews only' do
    approved_review(rating: 5, minutes_ago: 10)
    approved_review(rating: 5, minutes_ago: 9)
    approved_review(rating: 3, minutes_ago: 8)
    create(:review, store: store, product: product, user: create(:user), rating: 1, status: 'pending')
    create(:review, store: store, product: product, user: create(:user), rating: 1, status: 'rejected')

    get path, headers: headers

    distribution = json_response['meta']['rating_distribution']
    expect(distribution).to eq('1' => 0, '2' => 0, '3' => 1, '4' => 0, '5' => 2)
    expect(distribution.values.sum).to eq(json_response['meta']['count'])
    # 与商品聚合同源（只算 approved）
    expect(product.reload.review_count).to eq(3)
  end

  # PRD-20260916-catalog-batch-f1-reviews AC-008
  it 'never exposes photos of reviews that are not approved' do
    approved = create(:review, store: store, product: product, user: create(:user), rating: 5, status: 'approved')
    approved.images.attach(
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new('a' * 64), filename: 'approved.jpg',
                                             content_type: 'image/jpeg')
    )
    pending = create(:review, store: store, product: product, user: create(:user), rating: 1, status: 'pending')
    pending.images.attach(
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new('b' * 64), filename: 'pending.jpg',
                                             content_type: 'image/jpeg')
    )

    get path, headers: headers

    urls = json_response['data'].flat_map { |review| review['image_urls'] }
    expect(json_response['data'].map { |r| r['id'] }).to eq([approved.prefixed_id])
    expect(urls.size).to eq(1)
    expect(response.body).not_to include('pending.jpg')
  end
end
