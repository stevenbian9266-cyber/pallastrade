# frozen_string_literal: true

require 'rails_helper'

# PRD-20260818-catalog-p0-4-产品评论
# AC-001：Review 模型、唯一约束、默认 pending
RSpec.describe PallasTrade::Review, type: :model do
  let!(:store) { create(:store, code: 'rev_model_store') }
  let(:product) { create(:product, store: store) }
  let(:user) { create(:user) }

  it 'persists a review with default pending status' do
    review = create(:review, store: store, product: product, user: user, rating: 4)
    expect(review).to be_persisted
    expect(review.status).to eq('pending')
    expect(review).not_to be_approved
  end

  it 'enforces one review per (product, user)' do
    create(:review, store: store, product: product, user: user)
    duplicate = build(:review, store: store, product: product, user: user)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:product_id]).to be_present
  end

  it 'validates rating between 1 and 5' do
    expect(build(:review, store: store, product: product, user: user, rating: 6)).not_to be_valid
    expect(build(:review, store: store, product: product, user: user, rating: 0)).not_to be_valid
  end

  it 'supports approve! and reject!' do
    review = create(:review, store: store, product: product, user: user)
    review.approve!
    expect(review).to be_approved

    review.reject!
    expect(review.status).to eq('rejected')
    expect(review).not_to be_approved
  end

  it 'aggregates average rating and count over approved reviews' do
    create(:review, store: store, product: product, user: user, rating: 5).approve!
    other = create(:user)
    create(:review, store: store, product: product, user: other, rating: 3).approve!
    create(:review, store: store, product: product, user: create(:user), rating: 1) # pending, ignored

    expect(product.review_count).to eq(2)
    expect(product.average_rating).to eq(4.0)
  end
end
