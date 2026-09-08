# frozen_string_literal: true

# PRD-REV-P6-8b AC-R68B-06/07 —— Admin Refund Ops 人工 Retry / Mark for review（危险操作管控）
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe 'Admin Refund Ops manual actions', type: :request do
  let!(:store) { create(:store, code: 'refunds_ops_actions_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:reason) { create(:refund_reason) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::RefundsOpsController).
      to receive(:current_store).and_return(store)
  end

  def order_in
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 1000, total: 1000,
                   payment_state: 'balance_due')
  end

  def refund_in(state:)
    pm = create(:bogus_payment_method, store: store, active: true)
    payment = create(:payment, order: order_in, payment_method: pm, amount: 100,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)
    create(:refund, payment: payment, reason: reason, amount: 10, state: 'requested', transaction_id: nil)
      .tap do |r|
        r.update_columns(state: state, provider_idempotency_key: "refund:#{r.prefixed_id}:execute")
      end
  end

  describe 'AC-R68B-07 show 页按钮显隐（eligible + 权限）' do
    it 'ambiguous → 显示 Retry 与 Mark for review' do
      sign_in_as_superuser
      refund = refund_in(state: 'ambiguous')
      get "/admin/refunds/#{refund.prefixed_id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.orders.refunds_retry'))
      expect(response.body).to include(PallasTrade.t('admin.orders.refunds_mark_review'))
    end

    it 'succeeded → 不显示任何人工操作按钮' do
      sign_in_as_superuser
      refund = refund_in(state: 'succeeded')
      refund.update_columns(transaction_id: 're_ok')
      get "/admin/refunds/#{refund.prefixed_id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(PallasTrade.t('admin.orders.refunds_retry'))
      expect(response.body).not_to include(PallasTrade.t('admin.orders.refunds_mark_review'))
    end
  end

  describe 'AC-R68B-06 POST retry / mark_review' do
    it 'ambiguous retry → 状态 processing + ExecuteJob 入队 + 重定向 + success flash' do
      sign_in_as_superuser
      refund = refund_in(state: 'ambiguous')

      expect do
        post "/admin/refunds/#{refund.prefixed_id}/retry"
      end.to have_enqueued_job(PallasTrade::Refunds::ExecuteJob).with(refund.id)

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to("/admin/refunds/#{refund.prefixed_id}")
      expect(refund.reload.state).to eq('processing')
    end

    it 'succeeded retry → 拒绝（无入队）+ error flash' do
      sign_in_as_superuser
      refund = refund_in(state: 'succeeded')
      refund.update_columns(transaction_id: 're_done')

      expect do
        post "/admin/refunds/#{refund.prefixed_id}/retry"
      end.not_to have_enqueued_job(PallasTrade::Refunds::ExecuteJob)

      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response.body).to include('not eligible for manual retry')
    end

    it 'ambiguous mark_review → manual_review' do
      sign_in_as_superuser
      refund = refund_in(state: 'ambiguous')

      post "/admin/refunds/#{refund.prefixed_id}/mark_review"

      expect(response).to have_http_status(:redirect)
      expect(refund.reload.state).to eq('manual_review')
      expect(refund.last_error_code).to eq('OPERATOR_REVIEW')
    end

    it '无 update 权限 → 拒绝（302/403），状态不变' do
      sign_in admin
      limited_role = create(:role, name: "limited_#{SecureRandom.hex(4)}")
      create(:role_user, user: admin, role: limited_role, resource: store, store: store)
      refund = refund_in(state: 'ambiguous')

      expect do
        post "/admin/refunds/#{refund.prefixed_id}/retry"
      end.not_to have_enqueued_job(PallasTrade::Refunds::ExecuteJob)

      expect(response.status).to be_in([302, 403])
      expect(refund.reload.state).to eq('ambiguous')
    end
  end
end
