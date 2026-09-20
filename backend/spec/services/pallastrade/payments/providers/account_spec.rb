# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout 支付核心统一 · 切片 P0-B —— 账户配置写入原语（AC-1 / AC-2 / AC-3 / AC-6）
#
#   白名单：methods ∈ 能力声明；currencies ∈ 店铺支持币种；countries ∈ 店铺市场国家。
#   越界值忽略并回传 rejected；空选择 = 未声明（nil，不收窄）；同值重复写入幂等（不写库）。
RSpec.describe PallasTrade::Payments::Providers::Account do
  let!(:store) { create(:store, code: "p0b_account_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'P0B Account Store') }
  let(:gateway) { create(:stripe_gateway, store: store) }

  def allowed
    described_class.allowed_values(gateway)
  end

  describe 'AC-1 白名单' do
    it 'keeps declared kinds and rejects unknown ones' do
      outcome = described_class.write!(gateway, methods: ['card', 'Card', 'klarna'])

      expect(outcome['unchanged']).to be(false)
      expect(outcome['account']['methods']).to eq(%w[card])
      expect(outcome['rejected']['methods']).to eq(%w[klarna])
      expect(gateway.reload.provider_account_config['methods']).to eq(%w[card])
    end

    it 'keeps store currencies and rejects the rest' do
      store_currencies = Array(store.supported_currencies_list).map { |code| code.to_s.upcase }
      picked = store_currencies.first

      outcome = described_class.write!(gateway, currencies: [picked, 'XYZ'])

      expect(outcome['account']['currencies']).to eq([picked])
      expect(outcome['rejected']['currencies']).to eq(%w[XYZ])
    end

    it 'keeps store market countries and rejects the rest' do
      sample = Array(allowed['countries']).first

      outcome = described_class.write!(gateway, countries: [sample, 'ZZ'].compact)

      expect(outcome['rejected']['countries']).to include('ZZ')
      expect(Array(outcome['account']['countries'])).to all(be_in(Array(allowed['countries'])))
    end

    it 'treats an empty selection as undeclared (no narrowing) instead of "nothing allowed"' do
      outcome = described_class.write!(gateway, methods: [], currencies: [], countries: [])

      expect(outcome['account']['methods']).to be_nil
      expect(outcome['account']['currencies']).to be_nil
      expect(outcome['account']['countries']).to be_nil
      expect(outcome['account']['configured']).to be(false)
    end

    it 'ignores non-array input without raising' do
      outcome = described_class.write!(gateway, methods: 'card', currencies: nil, countries: 42)

      expect(outcome['ok']).to be(true)
      expect(outcome['account']['methods']).to be_nil
    end
  end

  describe 'AC-2 写入与幂等' do
    it 'marks the source as manual with audit stamps' do
      described_class.write!(gateway, methods: ['card'], actor: 'admin@example.com')

      account = gateway.reload.provider_account_config
      raw = gateway.metadata['account']

      expect(account['source']).to eq('manual')
      expect(account['synced_at']).to be_nil
      expect(raw['updated_at']).to be_present
      expect(raw['updated_by']).to eq('admin@example.com')
    end

    it 'is idempotent — an identical write changes nothing' do
      described_class.write!(gateway, methods: ['card'])
      first_stamp = gateway.reload.metadata['account']['updated_at']

      outcome = described_class.write!(gateway, methods: ['card'])

      expect(outcome['unchanged']).to be(true)
      expect(gateway.reload.metadata['account']['updated_at']).to eq(first_stamp)
    end
  end

  describe 'AC-3 零资金副作用' do
    it 'never touches payment records' do
      gateway # 建立 provider 记录（lazy let）后再取基线
      before_payments = PallasTrade::Payment.count
      before_sessions = PallasTrade::PaymentSession.count
      before_methods = PallasTrade::PaymentMethod.count

      described_class.write!(gateway, methods: ['card'], currencies: %w[USD])

      expect(PallasTrade::Payment.count).to eq(before_payments)
      expect(PallasTrade::PaymentSession.count).to eq(before_sessions)
      expect(PallasTrade::PaymentMethod.count).to eq(before_methods)
    end
  end

  describe 'AC-6 只读诊断与写入口一致' do
    it 'never flags an enabled option as undeclared when the account is recorded' do
      described_class.write!(gateway, methods: %w[card])

      codes = gateway.provider_diagnostics['issues'].map { |issue| issue['code'] }

      expect(codes).not_to include('kind_not_declared')
      expect(codes).not_to include('kind_not_in_account')
      expect(codes).not_to include('account_not_configured')
    end

    it 'falls back to the catalog when a provider declares capability without methods' do
      allow(gateway).to receive(:provider_capability_declaration).and_return('session_based' => true)

      capability = gateway.provider_capability

      expect(capability['source']).to eq('declared')
      expect(capability['method_keys']).to match_array(%w[card apple_pay google_pay])
      expect(gateway.provider_diagnostics['issues'].map { |issue| issue['code'] }).not_to include('kind_not_declared')
    end
  end
end
