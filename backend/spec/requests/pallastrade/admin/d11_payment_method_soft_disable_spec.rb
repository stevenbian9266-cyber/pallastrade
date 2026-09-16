# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d11-circuit-breaker-health（切片1，admin）
#   AC-007 ← FR-006：手动软置灰/解除可用（必填原因 + 审计）；「熔断与健康」卡渲染指标与状态；
#                    非管理员角色被拒（update 权限）
RSpec.describe 'Admin payment method circuit breaker (D11)', type: :request do
  let!(:store) do
    create(:store, code: "d11_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'D11 Store')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:payment_method) do
    create(:check_payment_method, store: store, active: true, display_on: 'both', name: 'D11 admin provider',
                                  metadata: { 'optionized' => true,
                                              'options' => [{ 'kind' => 'card', 'active' => true, 'position' => 1 }] })
  end

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-007
  it 'renders the breaker card with the health window and entry status' do
    sign_in_as_admin

    get "/admin/payment_methods/#{payment_method.prefixed_id}/edit"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('payment_method_breaker')
    expect(response.body).to include(PallasTrade.t('admin.payment_methods.breaker_window'))
    expect(response.body).to include(PallasTrade.t('admin.payment_methods.breaker_entry'))
    expect(response.body).to include(PallasTrade.t('admin.payment_methods.breaker_status_enabled'))
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-007
  it 'soft-disables an entry with a reason and records an audit entry' do
    sign_in_as_admin

    post "/admin/payment_methods/#{payment_method.prefixed_id}/soft_disable", params: { kind: 'card', reason: 'PSP incident' }

    expect(response).to have_http_status(:see_other)
    expect(payment_method.reload.soft_disabled?('card')).to be(true)

    state = payment_method.breaker_state('card')
    expect(state['reason']).to eq('PSP incident')
    expect(state['manual']).to be(true)

    audit = PallasTrade::AuditLog.where(action: 'payment_option_manually_soft_disabled').last
    expect(audit).to be_present
    expect(audit.resource_id).to eq(payment_method.id)
    expect(audit.metadata['kind']).to eq('card')
    expect(audit.metadata['reason']).to eq('PSP incident')
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-007
  it 'rejects a soft-disable without a reason' do
    sign_in_as_admin

    post "/admin/payment_methods/#{payment_method.prefixed_id}/soft_disable", params: { kind: 'card', reason: '  ' }

    expect(response).to have_http_status(:see_other)
    expect(flash[:error]).to eq(PallasTrade.t('admin.payment_methods.breaker_reason_required'))
    expect(payment_method.reload.soft_disabled?('card')).to be(false)
    expect(PallasTrade::AuditLog.where(action: 'payment_option_manually_soft_disabled').count).to eq(0)
  end

  # PRD-20260916-payments-d11-circuit-breaker-health AC-007
  it 're-enables a softened entry and records an audit entry' do
    sign_in_as_admin
    payment_method.soft_disable!(kind: 'card', reason: 'PSP incident', manual: true)

    post "/admin/payment_methods/#{payment_method.prefixed_id}/soft_enable", params: { kind: 'card' }

    expect(response).to have_http_status(:see_other)
    expect(payment_method.reload.soft_disabled?('card')).to be(false)
    expect(PallasTrade::AuditLog.where(action: 'payment_option_manually_soft_enabled').last.resource_id).
      to eq(payment_method.id)
  end
end
