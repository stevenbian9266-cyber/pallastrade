# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout 支付核心统一 · 切片 P0-A —— 厂商能力声明 / 账户配置 / 收窄（AC-1 / AC-2）
#
#   AC-1：`provider_capability` 对声明了 `provider_capability` 的 provider 取声明值；
#         未声明者由 `payment_option_catalog` + `session_required?` 推导（kind 集合一致）。
#   AC-2：`provider_account_config` 读 `metadata['account']`；缺失/非法 → manual + 各维度 nil（**不猜**）。
RSpec.describe PallasTrade::Payments::Providers::Config do
  let!(:store) { create(:store, code: "p0a_providers_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'P0A Store') }
  let(:gateway) { create(:stripe_gateway, store: store) }

  def write_metadata(payment_method, metadata)
    payment_method.update_columns(private_metadata: metadata)
    payment_method.reload
  end

  describe 'AC-1 能力声明' do
    it 'falls back to the provider catalog and marks the source as derived' do
      capability = gateway.provider_capability

      expect(capability['source']).to eq('derived')
      expect(capability['method_keys']).to match_array(%w[card apple_pay google_pay])
      # 未声明的维度一律 nil（不猜），不回落成"全部可用"
      expect(capability['currencies']).to be_nil
      expect(capability['countries']).to be_nil
      expect(capability['session_based']).to be(true)
    end

    it 'takes precedence of an explicit provider_capability declaration' do
      allow(gateway).to receive(:provider_capability_declaration).and_return(
        'methods' => %w[card],
        'currencies' => %w[usd eur],
        'countries' => %w[us de],
        'amount' => { 'min' => '1.00', 'max' => '50000.00' }
      )

      capability = gateway.provider_capability

      expect(capability['source']).to eq('declared')
      expect(capability['method_keys']).to eq(%w[card])
      expect(capability['currencies']).to eq(%w[USD EUR])
      expect(capability['countries']).to eq(%w[US DE])
      expect(capability['amount_min']).to eq(BigDecimal('1.00'))
      expect(capability['amount_max']).to eq(BigDecimal('50000.00'))
    end
  end

  describe 'AC-2 账户配置' do
    it 'returns an undeclared manual account when metadata has no account block' do
      account = gateway.provider_account_config

      expect(account['source']).to eq('manual')
      expect(account['configured']).to be(false)
      expect(account['methods']).to be_nil
      expect(account['currencies']).to be_nil
      expect(account['countries']).to be_nil
    end

    it 'ignores malformed values instead of raising' do
      write_metadata(gateway, 'account' => { 'source' => 'bogus', 'methods' => 'card', 'currencies' => [' usd '] })

      account = gateway.provider_account_config

      expect(account['source']).to eq('manual')
      expect(account['methods']).to be_nil
      expect(account['currencies']).to eq(%w[USD])
      expect(account['configured']).to be(true)
    end

    it 'normalizes a synced account (kinds downcased, ISO codes upcased, timestamp parsed)' do
      write_metadata(gateway, 'account' => {
                       'source' => 'synced',
                       'synced_at' => '2026-09-20T10:00:00Z',
                       'methods' => ['Card', 'apple_pay', 'card'],
                       'currencies' => %w[usd],
                       'countries' => %w[de]
                     })

      account = gateway.provider_account_config

      expect(account['source']).to eq('synced')
      expect(account['methods']).to eq(%w[card apple_pay])
      expect(account['currencies']).to eq(%w[USD])
      expect(account['countries']).to eq(%w[DE])
      expect(account['synced_at']).to be_present
    end
  end

  describe '收窄（能力 ∩ 账户）' do
    it 'narrows to the intersection and reports the basis' do
      allow(gateway).to receive(:provider_capability_declaration).and_return(
        'methods' => %w[card apple_pay], 'currencies' => %w[USD EUR]
      )
      write_metadata(gateway, 'account' => { 'methods' => %w[card], 'currencies' => %w[USD GBP] })

      effective = gateway.provider_effective_scope

      expect(effective['methods']['values']).to eq(%w[card])
      expect(effective['methods']['narrowed']).to be(true)
      expect(effective['methods']['basis']).to eq('capability+account')
      expect(effective['currencies']['values']).to match_array(%w[USD])
    end

    it 'does not narrow when one side is undeclared' do
      write_metadata(gateway, 'account' => { 'currencies' => %w[USD] })

      effective = gateway.provider_effective_scope

      expect(effective['currencies']['values']).to eq(%w[USD])
      expect(effective['currencies']['narrowed']).to be(false)
      expect(effective['currencies']['basis']).to eq('account')
      expect(effective['methods']['values']).to match_array(%w[card apple_pay google_pay])
      expect(effective['methods']['basis']).to eq('capability')
    end
  end

  describe '已配置适用范围（include 维度并集）' do
    it 'collects market/country/currency values from configured options' do
      write_metadata(gateway, {
                       'optionized' => true,
                       'options' => [
                         { 'kind' => 'card', 'active' => true, 'position' => 1,
                           'rule_set' => { 'include' => [
                             { 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[usd EUR] },
                             { 'dimension' => 'country', 'operator' => 'in', 'values' => %w[us] },
                             { 'dimension' => 'market', 'operator' => 'in', 'values' => %w[7] }
                           ] } },
                         { 'kind' => 'apple_pay', 'active' => true, 'position' => 2,
                           'rule_set' => { 'include' => [
                             { 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[gbp] }
                           ] } }
                       ]
                     })

      scope = described_class.configured_scope(gateway)

      expect(scope['currency']).to match_array(%w[USD EUR GBP])
      expect(scope['country']).to eq(%w[US])
      expect(scope['market']).to eq(%w[7])
    end

    it 'returns empty dimensions when nothing is configured' do
      scope = described_class.configured_scope(gateway)

      expect(scope).to eq('market' => [], 'country' => [], 'currency' => [], 'zone' => [])
    end
  end
end
