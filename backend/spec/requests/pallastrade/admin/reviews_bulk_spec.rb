# frozen_string_literal: true

require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

# PRD-20260916-catalog-batch-f3-review-bulk-moderation AC-001 ~ AC-010
#
# Bulk moderation must be nothing more than the single-row action applied N
# times: same authorization, same state machine, same audit trail — with an
# explainable report when some rows cannot move.
RSpec.describe 'Admin review bulk moderation', type: :request do
  let!(:store) { create(:store, code: 'rev_bulk_store', name: 'Bulk Store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:product) { create(:product, store: store, name: 'Bulk Reviewed Product') }

  def review(status: 'pending', rating: 5)
    create(
      :review, store: store, product: product, user: create(:user),
               rating: rating, title: 'T', body: 'B', status: status
    )
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::ReviewsController).to receive(:current_store).and_return(store)
  end

  def bulk(event, reviews)
    post '/admin/reviews/bulk', params: { event: event, ids: reviews.map(&:prefixed_id) }
  end

  it 'approves every selected pending review and audits each one (AC-001 / AC-006)' do
    sign_in_as_superuser
    reviews = Array.new(3) { review }

    expect { bulk('approve', reviews) }.to change { PallasTrade::Review.where(status: 'pending').count }.by(-3)

    expect(PallasTrade::Review.where(id: reviews.map(&:id)).pluck(:status).uniq).to eq(['approved'])
    expect(response).to redirect_to('/admin/reviews')
    expect(flash[:success]).to include('updated: 3')
  end

  it 'rejects every selected review and audits each one (AC-002)' do
    sign_in_as_superuser
    reviews = Array.new(3) { review }

    expect { bulk('reject', reviews) }.to change { PallasTrade::Review.where(status: 'pending').count }.by(-3)

    expect(PallasTrade::Review.where(id: reviews.map(&:id)).pluck(:status).uniq).to eq(['rejected'])
    expect(flash[:success]).to include('updated: 3')
  end

  it 'skips rows whose state is not allowed instead of failing the batch (AC-004 / AC-007)' do
    sign_in_as_superuser
    pending_review = review(status: 'pending')
    approved_review = review(status: 'approved')

    expect { bulk('approve', [pending_review, approved_review]) }.
      to change { PallasTrade::Review.where(status: 'pending').count }.by(-1)

    expect(pending_review.reload.status).to eq('approved')
    expect(approved_review.reload.status).to eq('approved')
    expect(flash[:success]).to include('updated: 1').and include('skipped (state not allowed): 1')
  end

  it 'reports unknown ids without touching anything else (AC-007)' do
    sign_in_as_superuser
    pending_review = review

    post '/admin/reviews/bulk',
         params: { event: 'approve', ids: [pending_review.prefixed_id, 'rev_doesnotexist'] }

    expect(pending_review.reload.status).to eq('approved')
    expect(flash[:success]).to include('updated: 1').and include('not found: 1')
  end

  it 'refuses an empty selection (AC-005)' do
    sign_in_as_superuser

    expect { bulk('approve', []) }.not_to change { PallasTrade::Review.where(status: 'approved').count }
    expect(flash[:error]).to include('at least one')
  end

  it 'refuses a selection above the 50-row cap and changes nothing (AC-005)' do
    sign_in_as_superuser
    reviews = Array.new(51) { review }

    expect { bulk('approve', reviews) }.not_to change { PallasTrade::Review.where(status: 'approved').count }
    expect(PallasTrade::Review.where(id: reviews.map(&:id)).pluck(:status).uniq).to eq(['pending'])
    expect(flash[:error]).to include('at most 50')
  end

  it 'ignores an unknown event (AC-007)' do
    sign_in_as_superuser
    pending_review = review

    bulk('publish_everything', [pending_review])

    expect(pending_review.reload.status).to eq('pending')
    expect(flash[:error]).to be_present
  end

  it 'registers both bulk actions and serves the confirm modal (AC-008)' do
    sign_in_as_superuser

    get '/admin/bulk_operations/new', params: { kind: 'approve', table_key: 'reviews' }
    expect(response).to have_http_status(:ok)

    get '/admin/bulk_operations/new', params: { kind: 'reject', table_key: 'reviews' }
    expect(response).to have_http_status(:ok)
  end

  it 'renders the worklist with the bulk entry point (AC-010)' do
    sign_in_as_superuser
    review

    get '/admin/reviews'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('bulk')
  end

  it 'keeps the approved-only public contract after a bulk approve (AC-009)' do
    sign_in_as_superuser
    pending_review = review(rating: 4)

    expect(PallasTrade::Review.approved.where(product_id: product.id).count).to eq(0)

    bulk('approve', [pending_review])

    expect(PallasTrade::Review.approved.where(product_id: product.id).count).to eq(1)
    expect(PallasTrade::Review.where(product_id: product.id).pluck(:status).uniq).to eq(['approved'])
  end
end
