# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d9-支付凭据与环境（切片2，admin）
#   AC-001 ← FR-001/002：保存环境（test → 强制前台不可见；live 不动可见性）
#   AC-004 ← FR-004：reveal 仅 owner 可用（无角色 → 403）；成功返回明文一次 + 审计（记 key 不记值）
#   AC-006 ← FR-006：Webhook 卡（端点 URL 含 prefixed_id + 签名密钥只读掩码）
RSpec.describe 'Admin payment method credentials (D9)', type: :request do
  let!(:store) { create(:store, code: "d9_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'D9 Store') }
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:gateway) { create(:stripe_gateway, store: store) }

  def sign_in_as_superuser
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  before do
    allow_any_instance_of(PallasTrade::Admin::PaymentMethodsController)
      .to receive(:location_after_save).and_return('/admin/payment_methods')
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-004
  it 'reveals a credential to the owner exactly once and audits the key (never the value)' do
    gateway
    sign_in_as_superuser

    post "/admin/payment_methods/#{gateway.prefixed_id}/reveal_credential",
         params: { key: 'secret_key' }, as: :json

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload['key']).to eq('secret_key')
    expect(payload['value']).to eq(gateway.reload.preferences[:secret_key])

    audit = PallasTrade::AuditLog.where(action: 'payment_method_credential_revealed').last
    expect(audit).to be_present
    expect(audit.metadata['key']).to eq('secret_key')
    expect(audit.metadata.to_json).not_to include(gateway.preferences[:secret_key].to_s)
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-004
  it 'refuses to reveal to an admin without the owner-equivalent role' do
    gateway
    sign_in admin

    post "/admin/payment_methods/#{gateway.prefixed_id}/reveal_credential",
         params: { key: 'secret_key' }, as: :json

    expect(response).to have_http_status(:forbidden).or have_http_status(:found)
    expect(PallasTrade::AuditLog.where(action: 'payment_method_credential_revealed').count).to eq(0)
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-004
  it 'rejects unknown credential keys (no plaintext, no audit)' do
    gateway
    sign_in_as_superuser

    post "/admin/payment_methods/#{gateway.prefixed_id}/reveal_credential",
         params: { key: 'not_a_credential' }, as: :json

    expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
    expect(PallasTrade::AuditLog.where(action: 'payment_method_credential_revealed').count).to eq(0)
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-006
  it 'renders the credential-health and webhook cards with masked values only' do
    gateway
    sign_in_as_superuser

    get "/admin/payment_methods/#{gateway.prefixed_id}/edit"
    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    expect(response.body).to include('/api/v3/webhooks/payments/')
    expect(doc.at_css("select[name='payment_method[environment]']")).to be_present
    expect(doc.at_css("#credential_value_secret_key")).to be_present

    secret = gateway.preferences[:secret_key]
    expect(response.body).not_to include(secret)
    expect(response.body).to include(PallasTrade::Preferences::Masking.mask(secret))
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-001
  it 'forces storefront_visible=false when switching to test and keeps live untouched' do
    gateway.update!(storefront_visible: true)
    sign_in_as_superuser

    patch "/admin/payment_methods/#{gateway.prefixed_id}",
          params: { payment_method: { name: gateway.name, environment: 'test' } }

    gateway.reload
    expect(gateway.environment).to eq('test')
    expect(gateway.storefront_visible).to be(false)

    patch "/admin/payment_methods/#{gateway.prefixed_id}",
          params: { payment_method: { name: gateway.name, environment: 'live' } }

    expect(gateway.reload.environment).to eq('live')
  end

  # PRD-20260915-payments-d9-支付凭据与环境 AC-007
  it 'ignores unknown environment values (zero regression for legacy forms)' do
    gateway
    sign_in_as_superuser

    patch "/admin/payment_methods/#{gateway.prefixed_id}",
          params: { payment_method: { name: 'Renamed', environment: 'staging' } }

    gateway.reload
    expect(gateway.name).to eq('Renamed')
    expect(gateway.environment).to eq('live')
  end
end
