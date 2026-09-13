# frozen_string_literal: true

# PRD-20260913-payments-dsp-p7-7-admin-disputes-console
# AC-P77-01..04、AC-P77-11、AC-P77-14 —— 列表（store 作用域 / 过滤 / 跨店隔离）、详情（§66 字段 / 降级）、表格注册。
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe 'Admin Disputes Ops pages', type: :request do
  let!(:store) { create(:store, code: "disputes_ops_#{SecureRandom.hex(4)}", default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::DisputesOpsController).
      to receive(:current_store).and_return(store)
  end

  def make_dispute(target_store: store, state: 'needs_response', attention_reason: nil,
                   funds_withdrawn_at: nil, reference: nil, link_payment: true, amount: 12.34,
                   provider_status: nil)
    payment_method = create(:bogus_payment_method, store: target_store, active: true)
    order = create(:order, store: target_store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: target_store.default_currency, email: 'dispute@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p77_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    transaction = PallasTrade::CommerceTransaction.create!(store: target_store, purpose: 'purchase',
                                                           currency: 'USD', amount: 100)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: reference || "dp_p77_#{SecureRandom.hex(4)}",
      state: state, amount: amount, currency: 'usd',
      attention_reason: attention_reason,
      funds_withdrawn_at: funds_withdrawn_at,
      private_metadata: provider_status ? { 'provider_status' => provider_status } : {},
      store_id: target_store.id,
      payment: link_payment ? payment : nil,
      order: link_payment ? order : nil,
      commerce_transaction: link_payment ? transaction : nil
    )
  end

  describe 'GET /admin/disputes' do
    it 'AC-P77-01 lists disputes of the current store and isolates other stores' do
      sign_in_as_superuser
      mine = make_dispute
      other_store = create(:store, code: "disp_other_#{SecureRandom.hex(4)}")
      theirs = make_dispute(target_store: other_store)

      get '/admin/disputes'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mine.prefixed_id)
      expect(response.body).not_to include(theirs.prefixed_id)
    end

    it 'AC-P77-02 Ransack whitelist filters by state' do
      sign_in_as_superuser
      lost = make_dispute(state: 'lost')
      open_dispute = make_dispute(state: 'needs_response')

      get '/admin/disputes', params: { q: { state_cont: 'lost' } }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(lost.prefixed_id)
      expect(response.body).not_to include(open_dispute.prefixed_id)
    end

    it 'AC-P77-14 table registry drives the list columns (id + state badge)' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'lost')

      table = PallasTrade.admin.tables.get(:disputes)
      expect(table).not_to be_nil
      expect(table.model_class).to eq(PallasTrade::Dispute)

      get '/admin/disputes'

      expect(response.body).to include(dispute.prefixed_id)
      expect(response.body).to include('Lost')
    end

    it 'AC-P77-10 无 read 权限 → 列表被拒' do
      sign_in admin
      role = create(:role, name: "Limited_#{SecureRandom.hex(4)}")
      create(:role_user, user: admin, role: role, resource: store, store: store)
      allow_any_instance_of(PallasTrade::Admin::DisputesOpsController).
        to receive(:current_store).and_return(store)
      dispute = make_dispute

      get '/admin/disputes'

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include(dispute.prefixed_id)
    end
  end

  describe 'GET /admin/disputes/:id' do
    it 'AC-P77-03 shows the §66 surface (anchors, journal, reconciliation, evidence, refund overlap)' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 2.hours, provider_status: 'lost')
      PallasTrade::FinancialLedger::PostDispute.call(dispute: dispute, fact_type: 'DISPUTE_FUNDS_WITHDRAWN')
      entry = PallasTrade::FinancialLedgerEntry.find_by(entry_type: 'DISPUTE_FUNDS_WITHDRAWN')
      expect(entry).to be_present

      get "/admin/disputes/#{dispute.prefixed_id}"

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include(dispute.prefixed_id)
      expect(body).to include(dispute.payment.prefixed_id)
      expect(body).to include(dispute.commerce_transaction.prefixed_id)
      expect(body).to include(dispute.order.number)
      expect(body).to include(dispute.provider_dispute_reference)
      expect(body).to include('Financial movements (journal)')
      expect(body).to include(entry.prefixed_id)
      expect(body).to include('Reconciliation')
      expect(body).to include('Evidence snapshot')
      expect(body).to include('Refund overlap')
      expect(body).to include('Provider truth')
    end

    it 'AC-P77-04 unlinked dispute degrades instead of failing (no payment anchor)' do
      sign_in_as_superuser
      dispute = make_dispute(attention_reason: 'unlinked_payment', link_payment: false)

      get "/admin/disputes/#{dispute.prefixed_id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(dispute.prefixed_id)
      expect(response.body).to include('No refunds')
    end

    it 'AC-P77-04 reconciliation/evidence exceptions degrade to nil without 500' do
      sign_in_as_superuser
      dispute = make_dispute
      # 服务类（ServiceModule）不可打桩 → 用可打桩的 AR 查询制造真实异常：
      # 对账与证据投影都要读账本 → 抛错 → 控制器逐项降级，页面仍 200
      allow(PallasTrade::FinancialLedgerEntry).to receive(:where).and_raise(StandardError, 'boom')

      get "/admin/disputes/#{dispute.prefixed_id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Reconciliation unavailable')
    end
  end

  describe 'AC-P77-11 跨店越权' do
    it 'refuses to read a dispute of another store (for_store scope keeps it out)' do
      sign_in_as_superuser
      other_store = create(:store, code: "disp_other2_#{SecureRandom.hex(4)}")
      theirs = make_dispute(target_store: other_store)

      begin
        get "/admin/disputes/#{theirs.prefixed_id}"
        # 未被作用域拦住则至少不能成功渲染
        expect(response).not_to have_http_status(:ok)
      rescue ActiveRecord::RecordNotFound, ActionController::Redirecting::OpenRedirectError => e
        # 预期路径：作用域找不到 → 404/重定向（spec 环境的 host 不匹配会抛 OpenRedirectError）
        expect(e).to be_present
      end

      expect(PallasTrade::Dispute.for_store(store).map(&:prefixed_id)).not_to include(theirs.prefixed_id)
    end
  end
end
