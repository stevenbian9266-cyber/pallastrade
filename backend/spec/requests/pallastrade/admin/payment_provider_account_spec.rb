# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout 支付核心统一 · 切片 P0-B —— 后台账户配置写入口（AC-4 / AC-5 / AC-7）
#
#   POST /admin/payment_methods/:id/update_provider_account
#   越界值忽略并回显；同值幂等；权限不足零写入；审计留痕。
RSpec.describe 'Admin payment provider account configuration', type: :request do
  let!(:store) { create(:store, code: "p0b_diag_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'P0B Diagnostics Store') }
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:gateway) { create(:stripe_gateway, store: store) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
  end

  def post_account(payload)
    post "/admin/payment_methods/#{gateway.prefixed_id}/update_provider_account",
         params: { provider_account: payload }
  end

  before do
    allow_any_instance_of(PallasTrade::Admin::PaymentMethodsController)
      .to receive(:location_after_save).and_return('/admin/payment_methods')
  end

  describe 'AC-4 保存后收窄生效' do
    it 'stores the account configuration and reflects it on the edit page' do
      sign_in_as_superuser
      post_account(methods: %w[card])

      expect(response).to have_http_status(:see_other)
      expect(gateway.reload.provider_account_config['methods']).to eq(%w[card])

      get "/admin/payment_methods/#{gateway.prefixed_id}/edit"
      doc = Nokogiri::HTML(response.body)
      card = doc.at_css("[data-testid='provider-diagnostics']")

      expect(card.at_css("[data-testid='provider-diagnostics-account']").text).to include('card')
      expect(card.text).not_to include('translation missing')
      expect(card.at_css("[data-testid='provider-account-form']")).to be_present
    end

    it 'narrows the effective methods with the account side' do
      sign_in_as_superuser
      post_account(methods: %w[card apple_pay])

      effective = gateway.reload.provider_effective_scope

      expect(effective['methods']['values']).to match_array(%w[card apple_pay])
      expect(effective['methods']['basis']).to eq('capability+account')
    end
  end

  describe 'AC-1 越界回显（不静默丢数据）' do
    it 'ignores unknown kinds and tells the operator' do
      sign_in_as_superuser
      post_account(methods: %w[card klarna])

      expect(gateway.reload.provider_account_config['methods']).to eq(%w[card])
      expect(flash[:warning]).to be_present
      expect(flash[:warning]).to include('klarna')
    end
  end

  describe 'AC-7 审计与幂等' do
    it 'records one audit entry per change' do
      sign_in_as_superuser
      expect(PallasTrade::Audit).to receive(:record).with(
        hash_including(action: 'payment_method_provider_account_updated')
      ).once

      post_account(methods: %w[card])
    end

    it 'is idempotent — the same payload twice does not raise and does not audit again' do
      sign_in_as_superuser
      post_account(methods: %w[card])
      expect(PallasTrade::Audit).not_to receive(:record).with(
        hash_including(action: 'payment_method_provider_account_updated')
      )

      post_account(methods: %w[card])

      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to be_present
    end
  end

  describe 'AC-5 权限' do
    it 'denies the write without update permission (zero writes)' do
      sign_in admin # 无 role_user → 无 update 权限
      before_metadata = gateway.private_metadata

      post_account(methods: %w[card])

      expect(response.status).to be_in([302, 403])
      expect(gateway.reload.private_metadata).to eq(before_metadata)
    end
  end
end
