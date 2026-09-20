# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout 支付核心统一 · 切片 P0-A —— 厂商配置收窄校验（AC-3 / AC-4 / AC-6）
#
#   判定链：静态能力 ∩ 账户配置 ∩ 市场范围。只读、不猜、零资金副作用。
RSpec.describe PallasTrade::Payments::Providers::Validate do
  let!(:store) { create(:store, code: "p0a_validate_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'P0A Validate Store') }
  let(:gateway) { create(:stripe_gateway, store: store) }

  def make_optionized!(payment_method, options)
    payment_method.update_columns(private_metadata: { 'optionized' => true, 'options' => options })
    payment_method.reload
  end

  def with_account!(payment_method, account)
    payment_method.update_columns(private_metadata: (payment_method.metadata || {}).merge('account' => account))
    payment_method.reload
  end

  def codes(payment_method)
    described_class.issues(payment_method).map { |issue| issue['code'] }
  end

  def issue_for(payment_method, code)
    described_class.issues(payment_method).find { |issue| issue['code'] == code }
  end

  describe 'AC-4 一致配置' do
    it 'reports no issues when the enabled options are declared and opened' do
      make_optionized!(gateway, [{ 'kind' => 'card', 'active' => true, 'position' => 1 }])
      with_account!(gateway, 'source' => 'manual', 'methods' => %w[card])

      summary = gateway.provider_diagnostics

      expect(summary['issues']).to be_empty
      expect(summary['ok']).to be(true)
      expect(summary['state']).to eq('enabled')
    end
  end

  describe 'AC-3 逐维度诊断' do
    it 'flags an enabled option the provider does not declare (error)' do
      make_optionized!(gateway, [
                         { 'kind' => 'card', 'active' => true, 'position' => 1 },
                         { 'kind' => 'klarna', 'active' => true, 'position' => 2 }
                       ])

      issue = issue_for(gateway, 'kind_not_declared')

      expect(issue).to be_present
      expect(issue['severity']).to eq('error')
      expect(issue['params']['kinds']).to eq('klarna')
      expect(gateway.provider_diagnostics['ok']).to be(false)
    end

    it 'flags an enabled option the account has not opened (warning, no error)' do
      make_optionized!(gateway, [
                         { 'kind' => 'card', 'active' => true, 'position' => 1 },
                         { 'kind' => 'apple_pay', 'active' => true, 'position' => 2 }
                       ])
      with_account!(gateway, 'methods' => %w[card])

      issue = issue_for(gateway, 'kind_not_in_account')

      expect(issue).to be_present
      expect(issue['severity']).to eq('warning')
      expect(issue['params']['kinds']).to eq('apple_pay')
      expect(gateway.provider_diagnostics['ok']).to be(true)
    end

    it 'says the account is not configured instead of guessing (info)' do
      make_optionized!(gateway, [{ 'kind' => 'card', 'active' => true, 'position' => 1 }])

      expect(codes(gateway)).to include('account_not_configured')
      expect(issue_for(gateway, 'account_not_configured')['severity']).to eq('info')
      # 未配置账户 → 不做账户级收窄（不猜）
      expect(gateway.provider_effective_scope['methods']['narrowed']).to be(false)
    end

    it 'flags currencies outside the account set' do
      make_optionized!(gateway, [{
                         'kind' => 'card', 'active' => true, 'position' => 1,
                         'rule_set' => { 'include' => [
                           { 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[USD EUR] }
                         ] }
                       }])
      with_account!(gateway, 'methods' => %w[card], 'currencies' => %w[USD])

      issue = issue_for(gateway, 'currency_not_available')

      expect(issue).to be_present
      expect(issue['params']['value']).to eq('EUR')
      expect(issue['params']['basis']).to eq('account')
    end

    it 'flags countries outside the account set' do
      make_optionized!(gateway, [{
                         'kind' => 'card', 'active' => true, 'position' => 1,
                         'rule_set' => { 'include' => [
                           { 'dimension' => 'country', 'operator' => 'in', 'values' => %w[US DE] }
                         ] }
                       }])
      with_account!(gateway, 'methods' => %w[card], 'countries' => %w[US])

      issue = issue_for(gateway, 'country_not_available')

      expect(issue).to be_present
      expect(issue['params']['value']).to eq('DE')
    end

    it 'does not flag currencies or countries when the scope is empty' do
      make_optionized!(gateway, [{ 'kind' => 'card', 'active' => true, 'position' => 1 }])
      with_account!(gateway, 'methods' => %w[card], 'currencies' => %w[USD], 'countries' => %w[US])

      expect(codes(gateway)).to be_empty
    end

    it 'notes a disabled provider that still has enabled options (info)' do
      make_optionized!(gateway, [{ 'kind' => 'card', 'active' => true, 'position' => 1 }])
      with_account!(gateway, 'methods' => %w[card])
      PallasTrade::Payments::Providers::State.disable!(gateway)

      issue = issue_for(gateway, 'disabled_with_active_options')

      expect(issue).to be_present
      expect(issue['severity']).to eq('info')
      expect(issue['params']['count']).to eq('1')
    end

    it 'warns when an optionized provider has no enabled option (invisible on the storefront)' do
      make_optionized!(gateway, [{ 'kind' => 'card', 'active' => false, 'position' => 1 }])
      with_account!(gateway, 'methods' => %w[card])

      issue = issue_for(gateway, 'no_active_options')

      expect(issue).to be_present
      expect(issue['severity']).to eq('warning')
    end

    it 'notes partially suspended options (info)' do
      make_optionized!(gateway, [
                         { 'kind' => 'card', 'active' => true, 'position' => 1 },
                         { 'kind' => 'apple_pay', 'active' => true, 'position' => 2 }
                       ])
      with_account!(gateway, 'methods' => %w[card apple_pay])
      PallasTrade::Payments::Providers::State.suspend!(gateway, kind: 'card', reason: 'down', until_at: 1.hour.from_now)

      issue = issue_for(gateway, 'partially_suspended')

      expect(issue).to be_present
      expect(issue['params']['kinds']).to eq('card')
    end
  end

  describe 'AC-6 零副作用' do
    it 'never writes configuration and never touches money records' do
      make_optionized!(gateway, [{ 'kind' => 'klarna', 'active' => true, 'position' => 1 }])
      before_metadata = gateway.reload.private_metadata
      before_updated_at = gateway.updated_at
      before_payments = PallasTrade::Payment.count
      before_sessions = PallasTrade::PaymentSession.count

      described_class.issues(gateway)
      gateway.provider_diagnostics

      gateway.reload
      expect(gateway.private_metadata).to eq(before_metadata)
      expect(gateway.updated_at).to eq(before_updated_at)
      expect(PallasTrade::Payment.count).to eq(before_payments)
      expect(PallasTrade::PaymentSession.count).to eq(before_sessions)
    end
  end
end
