# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13-reconciliation-cases（切片1，admin）
#   AC-006 ← FR-004：index 筛选/计数/show 渲染（含缺失关联降级）
#   AC-007 ← FR-004：动作（指派/备注/解释/修正/忽略/重开）写状态 + 审计；忽略必须填原因
#   AC-008 ← FR-004/FR-007：CSV 导出口径与筛选一致；无权限被拒
RSpec.describe 'Admin reconciliation cases (D13)', type: :request do
  let!(:store) do
    create(:store, code: "d13_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   name: 'D13 Store', url: 'https://d13.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:transaction) do
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase',
                                             currency: 'USD', amount: 100)
  end

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def build_case(**attrs)
    PallasTrade::ReconciliationCase.create!(
      { store: store, kind: 'transaction', commerce_transaction: transaction, status: 'open',
        difference_type: 'amount_mismatch', severity: 'critical', provider: 'stripe', currency: 'USD',
        expected_amount: 100, observed_amount: 95, reason_codes: ['AMOUNT_MISMATCH'],
        dedupe_key: "txn:#{transaction.id}:#{SecureRandom.hex(4)}",
        detected_at: Time.current, last_seen_at: Time.current }.merge(attrs)
    )
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-006
  it 'renders the queue with counters and applies filters' do
    sign_in_as_admin
    kept = build_case
    build_case(status: 'dismissed', severity: 'info', difference_type: 'needs_attention', provider: 'adyen',
               resolved_at: Time.current, resolution_source: 'human')

    get '/admin/reconciliation_cases'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.reconciliation_cases.title'))
    expect(response.body).to include(PallasTrade.admin_reconciliation_case_path(kept))

    get '/admin/reconciliation_cases', params: { provider: 'adyen' }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(PallasTrade.admin_reconciliation_case_path(kept))

    get '/admin/reconciliation_cases', params: { status: 'dismissed' }

    expect(response.body).to include('adyen')
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-006
  it 'renders a case detail page and degrades when the linked transaction is gone' do
    sign_in_as_admin
    case_record = build_case
    case_record.notes.create!(body: 'asked the provider', author: admin)

    get "/admin/reconciliation_cases/#{case_record.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('asked the provider')
    expect(response.body).to include(transaction.prefixed_id)
    expect(response.body).to include(PallasTrade.t('admin.reconciliation_cases.audit_trail'))

    orphan = build_case(commerce_transaction: nil, dedupe_key: "txn:none:#{SecureRandom.hex(4)}")
    get "/admin/reconciliation_cases/#{orphan.id}"

    expect(response).to have_http_status(:ok)
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-007
  it 'assigns, notes, closes, dismisses and reopens a case with audit entries' do
    sign_in_as_admin
    case_record = build_case

    post "/admin/reconciliation_cases/#{case_record.id}/assign", params: { assignee_id: 'self' }
    expect(case_record.reload.assignee_id).to eq(admin.id)
    expect(PallasTrade::AuditLog.where(action: 'reconciliation_case_assigned').count).to eq(1)

    post "/admin/reconciliation_cases/#{case_record.id}/note", params: { body: '   ' }
    expect(case_record.reload.notes.count).to eq(0)
    expect(flash[:error]).to eq(PallasTrade.t('admin.reconciliation_cases.note_required'))

    post "/admin/reconciliation_cases/#{case_record.id}/note", params: { body: 'contacted Stripe support' }
    expect(case_record.reload.notes.sole.body).to eq('contacted Stripe support')
    expect(PallasTrade::AuditLog.where(action: 'reconciliation_case_note_added').count).to eq(1)

    post "/admin/reconciliation_cases/#{case_record.id}/mark_investigating"
    expect(case_record.reload.status).to eq('investigating')
    expect(case_record.in_queue?).to be(true)

    post "/admin/reconciliation_cases/#{case_record.id}/mark_explained"
    expect(case_record.reload.status).to eq('explained')
    expect(case_record.resolution_source).to eq('human')
    expect(case_record.resolved_at).to be_present
    expect(PallasTrade::AuditLog.where(action: 'reconciliation_case_explained').count).to eq(1)

    post "/admin/reconciliation_cases/#{case_record.id}/reopen"
    expect(case_record.reload.status).to eq('open')
    expect(case_record.resolved_at).to be_nil
    expect(PallasTrade::AuditLog.where(action: 'reconciliation_case_reopened').count).to eq(1)

    post "/admin/reconciliation_cases/#{case_record.id}/dismiss", params: { reason: '  ' }
    expect(case_record.reload.status).to eq('open')
    expect(flash[:error]).to eq(PallasTrade.t('admin.reconciliation_cases.dismiss_reason_required'))

    post "/admin/reconciliation_cases/#{case_record.id}/dismiss", params: { reason: 'duplicate alert' }
    expect(case_record.reload.status).to eq('dismissed')
    expect(case_record.resolution_note).to eq('duplicate alert')
    expect(PallasTrade::AuditLog.where(action: 'reconciliation_case_dismissed').count).to eq(1)
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-007
  it 'does not let an unknown assignee change the case' do
    sign_in_as_admin
    case_record = build_case

    post "/admin/reconciliation_cases/#{case_record.id}/assign", params: { assignee_id: 999_999 }

    expect(case_record.reload.assignee_id).to be_nil
    expect(flash[:error]).to eq(PallasTrade.t('admin.reconciliation_cases.assignee_not_found'))
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-008
  it 'exports the filtered queue as CSV' do
    sign_in_as_admin
    kept = build_case
    build_case(provider: 'adyen', dedupe_key: "txn:x:#{SecureRandom.hex(4)}")

    get '/admin/reconciliation_cases/export', params: { provider: 'stripe' }

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Type']).to include('text/csv')
    lines = response.body.split("\n").reject(&:blank?)
    expect(lines.first).to include('dedupe_key')
    expect(lines.first).to include('resolution_source')
    expect(lines.size).to eq(2)
    expect(response.body).to include(kept.dedupe_key)
    expect(response.body).to include('AMOUNT_MISMATCH')
    expect(response.body).not_to include('adyen')
  end

  # PRD-20260916-payments-d13-reconciliation-cases AC-008
  it 'denies access to an admin without the reconciliation permission' do
    sign_in create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)

    get '/admin/reconciliation_cases'

    expect(response.status).to be_in([302, 303, 403])
  end
end
