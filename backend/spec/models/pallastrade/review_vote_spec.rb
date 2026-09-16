# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-batch-f5-helpful-vote AC-001 AC-002 AC-005 AC-006
#
#   AC-001 ← FR-001：一人一票由唯一约束保证（模型校验给出可读错误，索引兜底并发）
#   AC-002 ← FR-001：counter cache 与投票记录数一致（投票 +1 / 撤销 -1）
#   AC-005 ← FR-003：作者的自我投票被拒
#   AC-006 ← FR-003：只有 approved 评论可被投票
RSpec.describe PallasTrade::ReviewVote, type: :model do
  let(:store) { @default_store }
  let(:product) { create(:product, store: store) }
  let(:author) { create(:user) }
  let(:voter) { create(:user) }
  let(:review) { create(:review, store: store, product: product, user: author, status: 'approved') }

  it 'counts one vote per customer on the review (AC-001 / AC-002)' do
    expect { create(:review_vote, review: review, user: voter) }
      .to change { review.reload.helpful_votes_count }.from(0).to(1)
  end

  it 'refuses a second vote from the same customer (AC-001)' do
    create(:review_vote, review: review, user: voter)

    duplicate = build(:review_vote, review: review, user: voter)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:review_id]).to be_present
  end

  it 'refuses a vote from the review author (AC-005)' do
    vote = build(:review_vote, review: review, user: author)

    expect(vote).not_to be_valid
    expect(vote.errors[:user]).to be_present
  end

  it 'only accepts votes on approved reviews (AC-006)' do
    pending_review = create(
      :review, store: store, product: create(:product, store: store),
               user: author, status: 'pending'
    )

    vote = build(:review_vote, review: pending_review, user: voter)

    expect(vote).not_to be_valid
    expect(vote.errors[:review]).to be_present
  end

  it 'keeps the counter in sync when a vote is withdrawn (AC-002)' do
    vote = create(:review_vote, review: review, user: voter)

    expect { vote.destroy }.to change { review.reload.helpful_votes_count }.from(1).to(0)
  end

  it 'takes its votes with it when the review is deleted (AC-001)' do
    create(:review_vote, review: review, user: voter)

    expect { review.destroy }.to change(PallasTrade::ReviewVote, :count).by(-1)
  end
end
