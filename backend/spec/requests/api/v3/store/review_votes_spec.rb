# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-batch-f5-helpful-vote AC-003 AC-004 AC-005 AC-006 AC-007 AC-008
#
#   AC-003 ← FR-002：POST 幂等（重复请求不翻倍），响应携带权威状态
#   AC-004 ← FR-002：DELETE 撤销，且对未投过的评论幂等
#   AC-005 ← FR-003：自我投票 422（稳定码，不落库）
#   AC-006 ← FR-003：未审核评论 404；未登录 401
#   AC-007 ← FR-003：跨店 404（current_store 作用域）
#   AC-008 ← FR-004：字段只增；匿名请求 helpful_voted 为 null（绝不用 false 冒充答案）；不暴露投票者身份
RSpec.describe 'Store review helpful votes', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:product) { create(:product, store: store) }
  let(:author) { create(:user) }
  # Eager: the read-model examples assert on a list, so the review must exist
  # even when the example itself never touches the `review` helper.
  let!(:review) { create(:review, store: store, product: product, user: author, status: 'approved') }
  let(:path) { "/api/v3/store/reviews/#{review.prefixed_id}/helpful_vote" }
  let(:list_path) { "/api/v3/store/products/#{product.prefixed_id}/reviews" }

  describe 'POST /api/v3/store/reviews/:review_id/helpful_vote' do
    it 'records the vote and answers with the authoritative state (AC-003)' do
      post path, headers: headers

      expect(response).to have_http_status(:ok)
      attributes = json_response.dig('data', 'attributes')
      expect(attributes['helpful_votes_count']).to eq(1)
      expect(attributes['helpful_voted']).to be(true)
      expect(review.reload.helpful_votes_count).to eq(1)
    end

    it 'is idempotent — a repeated POST never double counts (AC-003)' do
      post path, headers: headers
      post path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response.dig('data', 'attributes', 'helpful_votes_count')).to eq(1)
      expect(PallasTrade::ReviewVote.where(review: review, user: user).count).to eq(1)
    end
  end

  describe 'DELETE /api/v3/store/reviews/:review_id/helpful_vote' do
    it 'withdraws an existing vote (AC-004)' do
      create(:review_vote, review: review, user: user, store: store)

      delete path, headers: headers

      expect(response).to have_http_status(:ok)
      attributes = json_response.dig('data', 'attributes')
      expect(attributes['helpful_votes_count']).to eq(0)
      expect(attributes['helpful_voted']).to be(false)
    end

    it 'is idempotent for a vote that was never cast (AC-004)' do
      delete path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(review.reload.helpful_votes_count).to eq(0)
    end
  end

  describe 'guards' do
    it 'forbids voting for your own review (AC-005)' do
      own_review = create(
        :review, store: store, product: create(:product, store: store),
                 user: user, status: 'approved'
      )

      post "/api/v3/store/reviews/#{own_review.prefixed_id}/helpful_vote", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response.dig('error', 'code')).to eq('own_review_vote_forbidden')
      expect(PallasTrade::ReviewVote.count).to eq(0)
    end

    it 'hides reviews that are not approved (AC-006)' do
      pending_review = create(
        :review, store: store, product: create(:product, store: store),
                 user: author, status: 'pending'
      )

      post "/api/v3/store/reviews/#{pending_review.prefixed_id}/helpful_vote", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(PallasTrade::ReviewVote.count).to eq(0)
    end

    it 'requires a customer JWT (AC-006)' do
      post path, headers: api_key_headers

      expect(response).to have_http_status(:unauthorized)
      expect(PallasTrade::ReviewVote.count).to eq(0)
    end

    it 'cannot reach a review that belongs to another store (AC-007)' do
      other_store = create(:store, code: 'other-review-store')
      other_review = create(
        :review, store: other_store, product: create(:product, store: other_store),
                 user: author, status: 'approved'
      )

      post "/api/v3/store/reviews/#{other_review.prefixed_id}/helpful_vote", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(PallasTrade::ReviewVote.count).to eq(0)
    end
  end

  describe 'read model (AC-008)' do
    it 'reports the count publicly and the caller state only when signed in' do
      create(:review_vote, review: review, user: user, store: store)

      get list_path, headers: headers
      signed_in = json_response['data'].first
      expect(signed_in['helpful_votes_count']).to eq(1)
      expect(signed_in['helpful_voted']).to be(true)
    end

    it 'answers null — not false — for anonymous callers' do
      get list_path, headers: api_key_headers

      anonymous = json_response['data'].first
      expect(anonymous['helpful_votes_count']).to eq(0)
      # `null` means "we were not asked"; `false` would claim the caller had
      # looked and decided against voting.
      expect(anonymous['helpful_voted']).to be_nil
    end

    it 'never exposes who voted' do
      create(:review_vote, review: review, user: user, store: store)

      get list_path, headers: headers

      item = json_response['data'].first
      expect(item.keys).not_to include('user_id', 'voter_id', 'voters')
      expect(response.body).not_to include(user.email)
    end
  end
end
