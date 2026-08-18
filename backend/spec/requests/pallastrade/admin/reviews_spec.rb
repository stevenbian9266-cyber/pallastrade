# frozen_string_literal: true

require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

# PRD-20260818-catalog-p0-4-产品评论
# AC-004：Admin 审核页（列表 + 审批/拒绝/删除）
RSpec.describe 'Admin reviews', type: :request do
  let!(:store) { create(:store, code: 'rev_admin_store', name: 'Rev Store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:product) { create(:product, store: store, name: 'Reviewed Product') }
  let!(:review) do
    user = create(:user, email: 'reviewer@example.com')
    create(:review, store: store, product: product, user: user, rating: 5, title: 'Amazing', body: 'Love it')
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::ReviewsController).to receive(:current_store).and_return(store)
  end

  it 'lists reviews for the current store' do
    sign_in_as_superuser
    get '/admin/reviews'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('reviewer@example.com')
    expect(response.body).to include(PallasTrade.t('admin.reviews.title'))
  end

  it 'approves a pending review' do
    sign_in_as_superuser
    patch "/admin/reviews/#{review.prefixed_id}/approve"
    expect(response).to have_http_status(:redirect)
    expect(review.reload).to be_approved
  end

  it 'rejects a pending review' do
    sign_in_as_superuser
    patch "/admin/reviews/#{review.prefixed_id}/reject"
    expect(response).to have_http_status(:redirect)
    expect(review.reload.status).to eq('rejected')
  end

  it 'deletes a review' do
    sign_in_as_superuser
    delete "/admin/reviews/#{review.prefixed_id}"
    expect(response).to have_http_status(:redirect)
    expect(PallasTrade::Review.exists?(review.id)).to be(false)
  end
end
