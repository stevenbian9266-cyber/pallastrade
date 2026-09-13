# frozen_string_literal: true

# PRD-20260913-payments-dsp-p7-7-admin-disputes-console
# AC-P77-05..10、AC-P77-12 —— 安全动作（刷新/预览/收敛/证据/人工标记）、幂等、权限、铁律负向断言、危险操作路由不存在。
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe 'Admin Disputes Ops actions', type: :request do
  let!(:store) { create(:store, code: "disputes_ops_actions_#{SecureRandom.hex(4)}", default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::DisputesOpsController).
      to receive(:current_store).and_return(store)
  end

  def make_dispute(state: 'opened', funds_withdrawn_at: nil, attention_reason: nil, reference: nil, link_payment: true)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'dispute_actions@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p77a_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    transaction = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase',
                                                           currency: 'USD', amount: 100)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: reference || "dp_p77a_#{SecureRandom.hex(4)}",
      state: state, amount: 12.34, currency: 'usd',
      attention_reason: attention_reason,
      funds_withdrawn_at: funds_withdrawn_at,
      store_id: store.id,
      payment: link_payment ? payment : nil,
      order: link_payment ? order : nil,
      commerce_transaction: link_payment ? transaction : nil
    )
  end

  # provider 只读快照（类级打桩：请求内 dispute 由 DB 重新载入 → 实例级 stub 会失效）
  def stub_provider(status:)
    allow_any_instance_of(payment_method.class).to receive(:fetch_dispute_details).and_return(
      { status: status, amount: BigDecimal('12.34'), currency: 'usd', observed_at: Time.current }
    )
  end

  def sign_in_as_no_permission
    sign_in admin
    role = create(:role, name: "Limited_#{SecureRandom.hex(4)}")
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::DisputesOpsController).
      to receive(:current_store).and_return(store)
  end

  # 铁律观测面：资金/订单/库存实体在动作前后必须逐字节不变
  def money_counts
    {
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      transactions: PallasTrade::CommerceTransaction.count,
      shipments: PallasTrade::Shipment.count,
      inventory_units: PallasTrade::InventoryUnit.count,
      stock_reservations: PallasTrade::StockReservation.count,
      disputes: PallasTrade::Dispute.count
    }
  end

  describe 'POST /admin/disputes/:id/refresh' do
    it 'AC-P77-05 refreshes provider state read-only and flashes the resolution' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'lost')
      stub_provider(status: 'lost')
      attributes_before = dispute.reload.attributes
      counts_before = money_counts

      post "/admin/disputes/#{dispute.prefixed_id}/refresh"

      expect(response).to have_http_status(:see_other)
      expect(flash[:success]).to include('aligned')
      expect(dispute.reload.attributes).to eq(attributes_before)
      expect(money_counts).to eq(counts_before)
    end

    it 'AC-P77-05 provider without a read contract degrades honestly (unsupported, zero write)' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'opened')

      post "/admin/disputes/#{dispute.prefixed_id}/refresh"

      expect(response).to have_http_status(:see_other)
      expect(flash[:success]).to include('unsupported')
      expect(dispute.reload.state).to eq('opened')
      expect(dispute.attention_reason).to be_nil
    end
  end

  describe 'POST /admin/disputes/:id/dry_run' do
    it 'AC-P77-07 previews the convergence plan without writing anything' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'opened', funds_withdrawn_at: Time.current - 2.hours)
      stub_provider(status: 'lost')
      attributes_before = dispute.reload.attributes
      counts_before = money_counts

      post "/admin/disputes/#{dispute.prefixed_id}/dry_run"

      expect(response).to have_http_status(:see_other)
      expect(flash[:success]).to include('lifecycle_and_journal_repaired')
      expect(dispute.reload.attributes).to eq(attributes_before)
      expect(money_counts).to eq(counts_before)
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
    end
  end

  describe 'POST /admin/disputes/:id/recover' do
    it 'AC-P77-06 converges idempotently (second run is a noop, no extra journal entry)' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'opened', funds_withdrawn_at: Time.current - 2.hours)
      stub_provider(status: 'lost')

      post "/admin/disputes/#{dispute.prefixed_id}/recover"

      expect(response).to have_http_status(:see_other)
      expect(flash[:success]).to include('lifecycle_and_journal_repaired')
      expect(dispute.reload.state).to eq('lost')
      entries_after_first = PallasTrade::FinancialLedgerEntry.count
      expect(entries_after_first).to eq(1)

      post "/admin/disputes/#{dispute.prefixed_id}/recover"

      expect(flash[:success]).to include('noop')
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(entries_after_first)
    end

    it 'AC-P77-08/12 keeps money entities untouched (recovery only repairs facts)' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'opened', funds_withdrawn_at: Time.current - 2.hours)
      stub_provider(status: 'lost')
      counts_before = money_counts

      post "/admin/disputes/#{dispute.prefixed_id}/recover"

      counts_after = money_counts
      expect(counts_after.except(:disputes)).to eq(counts_before.except(:disputes))
      expect(counts_after[:disputes]).to eq(counts_before[:disputes])
      expect(PallasTrade::Refund.count).to eq(0)
    end
  end

  describe 'POST /admin/disputes/:id/snapshot' do
    it 'AC-P77-09 builds the transient evidence snapshot (nothing stored, nothing submitted)' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 2.hours)
      attributes_before = dispute.reload.attributes
      counts_before = money_counts

      post "/admin/disputes/#{dispute.prefixed_id}/snapshot"

      expect(response).to have_http_status(:see_other)
      expect(flash[:success]).to include('missing item')
      expect(dispute.reload.attributes).to eq(attributes_before)
      expect(money_counts).to eq(counts_before)
    end
  end

  describe 'POST /admin/disputes/:id/mark_review' do
    it 'AC-P77-09 flags the dispute for human review with an audit trail' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'lost')

      expect do
        post "/admin/disputes/#{dispute.prefixed_id}/mark_review"
      end.to change { PallasTrade::AuditLog.where(action: 'dispute_mark_review').count }.by(1)

      expect(response).to have_http_status(:see_other)
      dispute.reload
      expect(dispute.state).to eq('manual_review')
      expect(dispute.attention_reason).to eq('operator_review')
      audit = PallasTrade::AuditLog.where(action: 'dispute_mark_review').last
      expect(audit.resource_prefixed_id).to eq(dispute.prefixed_id)
      expect(audit.after['state']).to eq('manual_review')
    end

    it 'AC-P77-09 never overwrites an existing attention reason and is idempotent' do
      sign_in_as_superuser
      dispute = make_dispute(state: 'lost', attention_reason: 'provider_conflict')

      post "/admin/disputes/#{dispute.prefixed_id}/mark_review"

      dispute.reload
      expect(dispute.state).to eq('manual_review')
      expect(dispute.attention_reason).to eq('provider_conflict')

      post "/admin/disputes/#{dispute.prefixed_id}/mark_review"

      expect(flash[:success]).to include('already')
      expect(dispute.reload.attention_reason).to eq('provider_conflict')
      expect(PallasTrade::AuditLog.where(action: 'dispute_mark_review').count).to eq(1)
    end
  end

  describe 'AC-P77-10 权限' do
    it 'rejects write actions without update permission and keeps zero write' do
      sign_in_as_no_permission
      dispute = make_dispute(state: 'opened')
      stub_provider(status: 'lost')
      state_before = dispute.reload.state
      counts_before = money_counts

      post "/admin/disputes/#{dispute.prefixed_id}/recover"

      expect(response).not_to have_http_status(:see_other)
      expect(dispute.reload.state).to eq(state_before)
      expect(money_counts).to eq(counts_before)
    end
  end

  describe 'AC-P77-12 危险操作在路由层面不存在' do
    it 'exposes no Accept Dispute / Submit Evidence endpoint' do
      helpers = Rails.application.routes.url_helpers

      expect(helpers).not_to respond_to(:accept_admin_dispute_path)
      expect(helpers).not_to respond_to(:submit_evidence_admin_dispute_path)
      dispute_routes = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
      expect(dispute_routes.none? { |path| path.include?('disputes') && path.match?(/accept|evidence/) }).to be(true)
    end
  end
end
