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

  # F-1 (PRD-20260916-catalog-batch-f1-reviews AC-007)：审核页内联展示评论图片
  context 'with reviewer photos' do
    let!(:photo) do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new('review-photo-bytes'),
        filename: 'photo.jpg',
        content_type: 'image/jpeg'
      )
      review.images.attach(blob)
      review.images.attachments.last
    end

    it 'renders the thumbnail and links to the full-size image' do
      sign_in_as_superuser
      url = Rails.application.routes.url_helpers.cdn_image_url(photo)
      get '/admin/reviews'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.reviews.photos'))
      expect(response.body).to include(url)
      expect(response.body).to include('object-cover')
    end

    it 'renders the empty placeholder for reviews without photos' do
      sign_in_as_superuser
      photo
      review.images.attachments.each { |attachment| attachment.purge }
      get '/admin/reviews'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('object-cover')
    end
  end
end
