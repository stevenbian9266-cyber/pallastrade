# frozen_string_literal: true

# TXN-P2-7 slice2 (REQ-20260905-txn-p2-7-admin-sweeper) AC-711/712/713/714
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe 'Admin Transactions pages', type: :request do
  let!(:store) { create(:store, code: 'txn_admin_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::TransactionsController).
      to receive(:current_store).and_return(store)
  end

  def make_transaction(state:)
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase',
      currency: store.default_currency.to_s.presence || 'USD', amount: 100
    )
    case state
    when 'payment_pending'
      tx.start_payment!
    when 'payment_confirmed'
      tx.start_payment!
      tx.confirm_payment!
    when 'finalizing'
      tx.start_payment!
      tx.confirm_payment!
      tx.begin_finalizing!
    when 'recovery_required'
      tx.start_payment!
      tx.confirm_payment!
      tx.mark_recovery_required!
    when 'manual_review'
      tx.start_payment!
      tx.confirm_payment!
      tx.mark_recovery_required!
      tx.manual_review!
    when 'completed'
      tx.start_payment!
      tx.confirm_payment!
      tx.begin_finalizing!
      tx.complete!
    end
    tx
  end

  describe 'GET /admin/transactions' do
    it 'AC-711 renders the store transaction list with metrics cards' do
      sign_in_as_superuser
      tx = make_transaction(state: 'recovery_required')

      get '/admin/transactions'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(tx.prefixed_id)
      expect(response.body).to include(PallasTrade.t('admin.orders.transactions_recovery_required'))
    end

    it 'AC-711 metrics reflect recovery_required count' do
      sign_in_as_superuser
      make_transaction(state: 'recovery_required')

      get '/admin/transactions'

      expect(response.body).to include('>1</div>') # recovery_required card count
    end
  end

  describe 'GET /admin/transactions/:id' do
    it 'AC-712 renders the trace read model' do
      sign_in_as_superuser
      tx = make_transaction(state: 'recovery_required')

      get "/admin/transactions/#{tx.prefixed_id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(tx.prefixed_id)
      expect(response.body).to include('recovery_required')
      expect(response.body).to include('Recovery')
    end
  end

  describe 'POST /admin/transactions/:id/recover' do
    it 'AC-713 enqueues RecoverJob for recovery_required' do
      sign_in_as_superuser
      tx = make_transaction(state: 'recovery_required')

      expect do
        post "/admin/transactions/#{tx.prefixed_id}/recover"
      end.to have_enqueued_job(PallasTrade::Transactions::RecoverJob).with(tx.prefixed_id)

      expect(response).to have_http_status(:redirect)
    end

    it 'AC-713 does not enqueue for a non-recoverable state (completed)' do
      sign_in_as_superuser
      tx = make_transaction(state: 'completed')

      expect do
        post "/admin/transactions/#{tx.prefixed_id}/recover"
      end.not_to have_enqueued_job(PallasTrade::Transactions::RecoverJob)

      expect(response).to have_http_status(:redirect)
    end

    it 'AC-713 manual_review never shows an automatic recover path (no enqueue)' do
      sign_in_as_superuser
      tx = make_transaction(state: 'manual_review')

      expect do
        post "/admin/transactions/#{tx.prefixed_id}/recover"
      end.not_to have_enqueued_job(PallasTrade::Transactions::RecoverJob)
    end
  end
end
