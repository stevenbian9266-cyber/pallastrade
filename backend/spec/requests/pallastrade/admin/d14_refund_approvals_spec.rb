# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14-refund-approval（切片1，admin）
#   AC-006 ← FR-005：审批工作台（待批队列/筛选/计数/策略卡/动作接线/不能自批/权限）
RSpec.describe 'Admin refund approvals (D14)', type: :request do
  let!(:store) do
    create(:store, code: "d14_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   name: 'D14 Store', url: 'https://d14.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:other_admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 200, total: 200,
                   payment_state: 'balance_due')
  end

  def sign_in_as_admin(user = admin)
    sign_in user
    create(:role_user, user: user, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def build_approval(requester_id: admin.id, status: 'pending', amount: 150, **attrs)
    own_order = create(:order, store: store, state: 'pending', status: 'placed',
                              item_total: 200, total: 200, payment_state: 'balance_due')
    payment = create(:payment, order: own_order, amount: 200, state: 'completed',
                               response_code: "ch_d14_admin_#{SecureRandom.hex(4)}")
    refund = create(:refund, payment: payment, amount: amount, refunder_id: requester_id, state: 'requested')
    PallasTrade::RefundApproval.create!(
      { store: store, refund: refund, status: status, amount: amount, currency: 'USD',
        requester_id: requester_id, decided_at: status == 'pending' ? nil : Time.current,
        policy_snapshot: { 'auto_approve_limit' => '100.0', 'currency' => nil } }.merge(attrs)
    )
  end

  # PRD-20260916-payments-d14-refund-approval AC-006
  it 'renders the pending queue with policy card, counts and filters' do
    sign_in_as_admin
    pending = build_approval
    decided = build_approval(status: 'rejected', note: 'too big')

    get '/admin/refund_approvals'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.refund_approvals.title'))
    expect(response.body).to include(PallasTrade.admin_refund_path(pending.refund))

    get '/admin/refund_approvals', params: { status: 'terminal' }

    expect(response.body).to include(PallasTrade.admin_refund_path(decided.refund))
    expect(response.body).not_to include(PallasTrade.approve_admin_refund_approval_path(pending))
  end

  # PRD-20260916-payments-d14-refund-approval AC-006（不能自批：本人行无动作）
  it 'hides decision actions on the requester own row' do
    sign_in_as_admin
    mine = build_approval(requester_id: admin.id)
    theirs = build_approval(requester_id: other_admin.id)

    get '/admin/refund_approvals'

    expect(response.body).to include(PallasTrade.t('admin.refund_approvals.own_request_hint'))
    expect(response.body).to include(PallasTrade.approve_admin_refund_approval_path(theirs))
    expect(response.body).not_to include(PallasTrade.approve_admin_refund_approval_path(mine))
  end

  # PRD-20260916-payments-d14-refund-approval AC-006
  it 'approves and rejects through the services with audit + flash' do
    sign_in_as_admin(other_admin)
    approval = build_approval(requester_id: admin.id)

    post "/admin/refund_approvals/#{approval.id}/approve", params: { note: 'looks fine' }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(PallasTrade.admin_refund_approvals_path)
    expect(approval.reload.status).to eq('approved')
    expect(approval.approver_id).to eq(other_admin.id)
    expect(PallasTrade::AuditLog.find_by(action: 'refund_approval_approved')).to be_present

    second = build_approval(requester_id: admin.id)
    post "/admin/refund_approvals/#{second.id}/reject"

    follow_redirect!
    expect(response.body).to include(PallasTrade.t('admin.refund_approvals.errors.note_required'))
    expect(second.reload.status).to eq('pending')

    post "/admin/refund_approvals/#{second.id}/reject", params: { note: 'policy' }

    expect(second.reload.status).to eq('rejected')
    expect(second.refund.reload.state).to eq('canceled')
  end

  # PRD-20260916-payments-d14-refund-approval AC-006（服务层强制不能自批）
  it 'refuses a self-approval submitted directly' do
    sign_in_as_admin(admin)
    approval = build_approval(requester_id: admin.id)

    post "/admin/refund_approvals/#{approval.id}/approve", params: { note: 'self' }

    expect(approval.reload.status).to eq('pending')
    follow_redirect!
    expect(response.body).to include(PallasTrade.t('admin.refund_approvals.errors.approver_must_differ'))
  end

  # PRD-20260916-payments-d14-refund-approval AC-006（策略卡保存 + 审计 + 归一化）
  it 'saves the refund policy and audits the change' do
    sign_in_as_admin

    patch '/admin/refund_approvals/policy', params: { enabled: '1', auto_approve_limit: '250.5', currency: 'usd' }

    expect(response).to have_http_status(:see_other)
    policy = PallasTrade::Refunds::Policy.for(store.reload)
    expect(policy.enabled?).to be(true)
    expect(policy.auto_approve_limit).to eq(BigDecimal('250.5'))
    expect(policy.currency).to eq('USD')

    audit = PallasTrade::AuditLog.find_by(action: 'refund_policy_updated')
    expect(audit.after['refund_policy']['auto_approve_limit']).to eq('250.5')

    # 关闭策略
    patch '/admin/refund_approvals/policy', params: { auto_approve_limit: '250.5' }
    expect(PallasTrade::Refunds::Policy.for(store.reload).enabled?).to be(false)
  end

  # PRD-20260916-payments-d14-refund-approval AC-006（权限）
  it 'denies access without the refund approval permission' do
    approval = build_approval

    get '/admin/refund_approvals'

    expect(response).not_to have_http_status(:ok)

    post "/admin/refund_approvals/#{approval.id}/approve"

    expect(approval.reload.status).to eq('pending')
    expect(response).not_to have_http_status(:ok)
  end
end
