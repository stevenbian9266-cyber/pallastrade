# frozen_string_literal: true

# D2（PRD-20260917-payments-d2-manual-review-审核动作-通过并捕获-拒绝并释放）
# AC-009..011：排障台人工裁决入口（通过并捕获 / 拒绝并释放）+ 非复核状态无按钮。
require 'rails_helper'

RSpec.describe 'Admin transaction manual review', type: :request do
  let!(:store) { create(:store, code: 'd2_review_admin_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:payment_method) { create(:bogus_payment_method, stores: [store], active: true) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::TransactionsController).
      to receive(:current_store).and_return(store)
  end

  def make_transaction(state:)
    tx = PallasTrade::CommerceTransaction.create!(
      store: store, purpose: 'purchase', currency: store.default_currency.to_s.presence || 'USD', amount: 100
    )
    tx.start_payment!
    tx.confirm_payment!
    case state
    when 'recovery_required'
      tx.mark_recovery_required!
    when 'manual_review'
      tx.mark_recovery_required!
      tx.manual_review!
    when 'finalizing'
      tx.begin_finalizing!
    when 'completed'
      tx.begin_finalizing!
      tx.complete!
    end
    tx
  end

  def participant_order
    order = create(:order_with_line_items, store: store, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         payment_state: nil, completed_at: nil)
    order.reload
  end

  def attach_participant(transaction)
    order = participant_order
    PallasTrade::TransactionOrder.create!(commerce_transaction: transaction, order: order,
                                          role: 'primary', amount_snapshot: order.total)
    order
  end

  def authorized_payment(order, transaction, amount: order.total)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             status: 'pending', amount: amount,
                                             currency: order.currency.to_s, commerce_transaction: transaction)
    create(:payment, order: order, payment_method: payment_method, amount: amount,
                     state: 'pending', payment_session: session)
  end

  describe 'POST /admin/transactions/:id/approve_and_capture' do
    it 'AC-009 captures and completes the transaction (302 + success flash)' do
      sign_in_as_superuser
      tx = make_transaction(state: 'manual_review')
      order = attach_participant(tx)
      payment = authorized_payment(order, tx)

      post "/admin/transactions/#{tx.prefixed_id}/approve_and_capture", params: { reason: 'provider says paid' }

      expect(response).to have_http_status(:see_other)
      expect(tx.reload).to be_completed
      expect(payment.reload).to be_completed
      expect(order.reload).to be_completed
      expect(flash[:success]).to eq(PallasTrade.t('admin.orders.transaction_review_capture_done'))
    end

    it 'AC-010 refuses without a reason and leaves the transaction in manual_review' do
      sign_in_as_superuser
      tx = make_transaction(state: 'manual_review')
      order = attach_participant(tx)
      authorized_payment(order, tx)

      post "/admin/transactions/#{tx.prefixed_id}/approve_and_capture", params: { reason: '' }

      expect(response).to have_http_status(:see_other)
      expect(tx.reload).to be_manual_review
      expect(flash[:error]).to eq(PallasTrade.t('admin.orders.transaction_review_error_reason_required'))
    end

    it 'AC-010 refuses without a pending authorization (no guessing)' do
      sign_in_as_superuser
      tx = make_transaction(state: 'manual_review')
      attach_participant(tx)

      post "/admin/transactions/#{tx.prefixed_id}/approve_and_capture", params: { reason: 'provider says paid' }

      expect(tx.reload).to be_manual_review
      expect(flash[:error]).to eq(PallasTrade.t('admin.orders.transaction_review_error_no_pending_authorization'))
    end

    it 'AC-009 denies the verdict without update permission and moves no money' do
      sign_in admin # 未授予任何角色
      allow_any_instance_of(PallasTrade::Admin::TransactionsController).
        to receive(:current_store).and_return(store)
      tx = make_transaction(state: 'manual_review')
      order = attach_participant(tx)
      payment = authorized_payment(order, tx)

      post "/admin/transactions/#{tx.prefixed_id}/approve_and_capture", params: { reason: 'provider says paid' }

      expect(response).not_to have_http_status(:ok)
      expect(tx.reload).to be_manual_review
      expect(payment.reload).to be_pending
      expect(PallasTrade::Refund.count).to eq(0)
      expect(PallasTrade::AuditLog.where(action: PallasTrade::Transactions::Review::AUDIT_CAPTURED)).to be_empty
    end
  end

  describe 'POST /admin/transactions/:id/release_and_cancel' do
    it 'AC-009 releases the authorization, cancels the order and cancels the transaction' do
      sign_in_as_superuser
      tx = make_transaction(state: 'manual_review')
      order = attach_participant(tx)
      payment = authorized_payment(order, tx)

      post "/admin/transactions/#{tx.prefixed_id}/release_and_cancel", params: { reason: 'provider says unpaid' }

      expect(response).to have_http_status(:see_other)
      expect(tx.reload).to be_canceled
      expect(order.reload).to be_canceled
      expect(payment.reload.state).to eq('void')
      expect(PallasTrade::Refund.count).to eq(0)
      expect(flash[:success]).to eq(PallasTrade.t('admin.orders.transaction_review_release_done'))
    end
  end

  describe 'GET /admin/transactions/:id' do
    it 'AC-011 renders the two verdict actions for manual_review' do
      sign_in_as_superuser
      tx = make_transaction(state: 'manual_review')
      order = attach_participant(tx)
      authorized_payment(order, tx)

      get "/admin/transactions/#{tx.prefixed_id}"

      expect(response).to have_http_status(:ok)
      # 按钮 label 渲染时 HTML 转义（& → &amp;）
      expect(response.body).to include(CGI.escapeHTML(PallasTrade.t('admin.orders.transaction_review_capture_action')))
      expect(response.body).to include(CGI.escapeHTML(PallasTrade.t('admin.orders.transaction_review_release_action')))
      expect(response.body).to include("/admin/transactions/#{tx.prefixed_id}/approve_and_capture")
      expect(response.body).to include("/admin/transactions/#{tx.prefixed_id}/release_and_cancel")
    end

    it 'AC-011 shows no verdict action for a non-review state' do
      sign_in_as_superuser
      tx = make_transaction(state: 'recovery_required')

      get "/admin/transactions/#{tx.prefixed_id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.orders.transaction_review_not_in_review'))
      expect(response.body).not_to include("/admin/transactions/#{tx.prefixed_id}/approve_and_capture")
      expect(response.body).not_to include("/admin/transactions/#{tx.prefixed_id}/release_and_cancel")
    end

    it 'AC-004 the review history surfaces the audit trail' do
      sign_in_as_superuser
      tx = make_transaction(state: 'manual_review')
      order = attach_participant(tx)
      authorized_payment(order, tx)
      post "/admin/transactions/#{tx.prefixed_id}/approve_and_capture", params: { reason: 'provider says paid' }

      get "/admin/transactions/#{tx.prefixed_id}"

      expect(response.body).to include(PallasTrade.t('admin.orders.transaction_review_history'))
      expect(response.body).to include(PallasTrade::Transactions::Review::AUDIT_CAPTURED)
      expect(response.body).to include('provider says paid')
    end
  end
end
