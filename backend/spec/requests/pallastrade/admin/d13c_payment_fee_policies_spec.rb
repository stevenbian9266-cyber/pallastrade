# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13c-fee-cost-report（D13 切片3，后台）
#   AC-11 ← FR-5：费率维护列表（计数同源）+ 新增 / 更新 / 撤销 + 审计 + 权限 + 校验回显
RSpec.describe 'Admin payment fee policies (D13c)', type: :request do
  let!(:store) do
    create(:store, code: "d13c_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   name: 'D13c Fee Store', url: 'https://d13c-fee.example.com',
                   mail_from_address: 'no-reply@d13c-fee.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:suffix) { SecureRandom.hex(4) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def stub_current_store!
    allow_any_instance_of(PallasTrade::Admin::PaymentFeePoliciesController)
      .to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::PaymentCostsController)
      .to receive(:current_store).and_return(store)
  end

  def audit_actions
    PallasTrade::AuditLog.where(resource_type: 'PallasTrade::PaymentFeePolicy').pluck(:action)
  end

  it 'renders the list with counts sourced from the same filters' do
    sign_in_as_admin
    stub_current_store!
    create(:payment_fee_policy, store: store, name: "live-#{suffix}")
    revoked = create(:payment_fee_policy, store: store, name: "gone-#{suffix}")
    revoked.revoke!(actor: 'spec')

    get '/admin/payment_fee_policies'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.payment_fee_policies.title'))
    expect(response.body).to include("live-#{suffix}")
    expect(response.body).to include("gone-#{suffix}")

    %w[all active revoked].each do |status_filter|
      expected = PallasTrade::PaymentFeePolicy.filter_by(
        store: store, status_filter: status_filter == 'all' ? nil : status_filter
      ).count
      expect(response.body).to include(%(data-count-scope="#{status_filter}">#{expected}</h3>))
    end
  end

  it 'creates a policy and records the change in the audit log' do
    sign_in_as_admin
    stub_current_store!

    expect do
      post '/admin/payment_fee_policies', params: { payment_fee_policy: {
        name: "created-#{suffix}", scope_type: 'method', scope_id: 'card', currency: 'usd',
        percent_fee: '2.4', fixed_fee: '0.25', platform_percent: '0.5'
      } }
    end.to change(PallasTrade::PaymentFeePolicy, :count).by(1)

    expect(response).to have_http_status(:see_other)
    policy = PallasTrade::PaymentFeePolicy.find_by(name: "created-#{suffix}")
    expect(policy.store_id).to eq(store.id)
    expect(policy.currency).to eq('USD')
    expect(policy.scope_id).to eq('card')
    expect(audit_actions).to include('payment_fee_policy_changed')
  end

  it 're-renders the form with errors when validation fails (no row created)' do
    sign_in_as_admin
    stub_current_store!

    expect do
      post '/admin/payment_fee_policies', params: { payment_fee_policy: {
        name: "bad-#{suffix}", scope_type: 'provider', percent_fee: '150'
      } }
    end.not_to change(PallasTrade::PaymentFeePolicy, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'updates a policy and audits before/after' do
    sign_in_as_admin
    stub_current_store!
    policy = create(:payment_fee_policy, store: store, name: "update-#{suffix}", percent_fee: 2.9)

    patch "/admin/payment_fee_policies/#{policy.id}", params: { payment_fee_policy: { percent_fee: '1.75' } }

    expect(response).to have_http_status(:see_other)
    expect(policy.reload.percent_fee.to_d).to eq(1.75.to_d)
    audit = PallasTrade::AuditLog.where(resource_type: 'PallasTrade::PaymentFeePolicy')
                                 .order(:id).last
    expect(audit.action).to eq('payment_fee_policy_changed')
    expect(audit.before['percent_fee']).to eq('2.9')
    expect(audit.after['percent_fee']).to eq('1.75')
  end

  it 'revokes a policy without deleting the row' do
    sign_in_as_admin
    stub_current_store!
    policy = create(:payment_fee_policy, store: store, name: "revoke-#{suffix}")

    expect do
      post "/admin/payment_fee_policies/#{policy.id}/revoke"
    end.not_to change(PallasTrade::PaymentFeePolicy, :count)

    expect(response).to have_http_status(:see_other)
    expect(policy.reload.status).to eq('revoked')
    expect(audit_actions).to include('payment_fee_policy_revoked')
  end

  it 'denies the page without the permission' do
    other_admin = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    sign_in other_admin
    stub_current_store!

    get '/admin/payment_fee_policies'

    expect(response).not_to have_http_status(:ok)
  end
end
