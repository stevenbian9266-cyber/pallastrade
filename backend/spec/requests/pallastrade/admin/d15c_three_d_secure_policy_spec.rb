# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-checkout-d15-切片3（D15 切片3，后台）
#   AC-014 ← FR-008：门店 3DS 策略区块保存/校验/审计；支付方式入口表显示「可强制认证」列（只读）
RSpec.describe 'Admin 3DS policy (D15c)', type: :request do
  let(:store) do
    create(:store, code: "d15c-admin-#{SecureRandom.hex(4)}", name: 'D15c Admin Store',
                   default: true, default_currency: 'USD', default_locale: 'en',
                   url: 'https://d15c-admin.example.com', mail_from_address: 'no-reply@d15c-admin.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def policy_metadata
    store.reload.private_metadata.to_h[PallasTrade::Payments::ThreeDSecure::Policy::STORE_METADATA_KEY]
  end

  # AC-014（保存策略：归一化 + 落库 + 审计）
  it 'stores a normalized policy and records an audit entry' do
    sign_in_as_admin

    expect do
      patch '/admin/store', params: {
        store: { name: store.name },
        three_d_secure_policy: { mode: 'always', low_amount_threshold: '25',
                                 allowlisted_countries: 'de, fr', allowlisted_option_kinds: 'card' }
      }
    end.to change(PallasTrade::AuditLog, :count).by(1)

    expect(policy_metadata).to eq(
      'mode' => 'always', 'low_amount_threshold' => '25.0',
      'allowlisted_countries' => %w[DE FR], 'allowlisted_option_kinds' => %w[card]
    )
    audit = PallasTrade::AuditLog.order(:id).last
    expect(audit.action).to eq('store_three_d_secure_policy_updated')
    expect(audit.after).to include('mode' => 'always')
  end

  # AC-014（非法值 → 不落库）
  it 'refuses invalid policy values without writing them' do
    sign_in_as_admin

    patch '/admin/store', params: {
      store: { name: store.name },
      three_d_secure_policy: { mode: 'sometimes', low_amount_threshold: '-1', allowlisted_countries: 'nope' }
    }

    expect(policy_metadata).to be_nil
    expect(flash[:error]).to be_present
  end

  # AC-014（未提交该键 → 零影响：不改动 metadata）
  it 'leaves the metadata untouched when the policy is not submitted' do
    store.update!(private_metadata: { 'some_existing_key' => 'kept' })
    sign_in_as_admin

    patch '/admin/store', params: { store: { name: store.name } }

    expect(store.reload.private_metadata).to eq('some_existing_key' => 'kept')
  end

  # AC-014（门店表单渲染策略区块）
  #
  # ⚠️ 收敛切片 6（2026-09-21，payment-convergence-stripe-only §9.1）：后台支付方式页的
  #    「可强制认证」列已随后台收敛**下线**，故本用例由「断言该列存在」改为
  #    「断言该列不再渲染」——策略区块本身的回归保护保持不变；
  #    认证闸门的**行为**由 `../services/.../d15c_policy_spec.rb` 与
  #    `../../api/v3/store/checkout/d7_entries_spec.rb`（3DS 剔除钱包入口）继续覆盖。
  it 'renders the policy block and no longer renders the option capability column' do
    sign_in_as_admin
    create(:stripe_gateway, store: store, active: true, display_on: 'front_end', name: 'D15c card provider')

    get '/admin/store/edit', params: { section: 'checkout' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-three-d-secure-policy-mode="risk_based"')
    expect(response.body).to include('three_d_secure_policy[mode]')
    expect(response.body).to include('three_d_secure_policy[low_amount_threshold]')

    get "/admin/payment_methods/#{store.payment_methods.last.prefixed_id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('data-payment-option-three-d-secure')
  end
end
