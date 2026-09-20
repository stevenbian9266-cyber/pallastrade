# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout 支付核心统一 · 切片 P0-A —— 厂商三态（AC-5）
#
#   enabled   = active 且无熔断；disabled = 人工停用（**粘性**，resume! 不恢复）；suspended = 熔断。
#   优先级：disabled > suspended > enabled。
RSpec.describe PallasTrade::Payments::Providers::State do
  let!(:store) { create(:store, code: "p0a_state_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'P0A State Store') }
  let(:gateway) { create(:stripe_gateway, store: store) }

  def make_optionized!(payment_method, options)
    payment_method.update_columns(private_metadata: { 'optionized' => true, 'options' => options })
    payment_method.reload
  end

  describe 'AC-5 三态读取' do
    it 'is enabled by default' do
      expect(described_class.state(gateway)).to eq('enabled')
    end

    it 'is disabled when the provider is switched off by a human' do
      gateway.update_columns(active: false)

      expect(described_class.state(gateway)).to eq('disabled')
    end

    it 'is suspended while a manual breaker is open' do
      described_class.suspend!(gateway, reason: 'manual hold', manual: true)

      expect(described_class.state(gateway)).to eq('suspended')
    end

    it 'auto-recovers when an automatic breaker window has passed' do
      described_class.suspend!(gateway, reason: 'auto', until_at: 1.hour.ago)

      expect(described_class.state(gateway)).to eq('enabled')
    end

    it 'stays suspended (not enabled) when every option is broken' do
      make_optionized!(gateway, [
                         { 'kind' => 'card', 'active' => true, 'position' => 1 },
                         { 'kind' => 'apple_pay', 'active' => true, 'position' => 2 }
                       ])
      described_class.suspend!(gateway, kind: 'card', reason: 'card down', manual: true)
      described_class.suspend!(gateway, kind: 'apple_pay', reason: 'wallet down', manual: true)

      expect(described_class.state(gateway)).to eq('suspended')
    end

    it 'stays enabled but reports suspended kinds when only part of the options are broken' do
      make_optionized!(gateway, [
                         { 'kind' => 'card', 'active' => true, 'position' => 1 },
                         { 'kind' => 'apple_pay', 'active' => true, 'position' => 2 }
                       ])
      described_class.suspend!(gateway, kind: 'card', reason: 'card down', until_at: 1.hour.from_now)

      expect(described_class.state(gateway)).to eq('enabled')
      expect(described_class.suspended_kinds(gateway)).to eq(%w[card])
    end
  end

  describe 'AC-5 写入原语' do
    it 'makes a manual disable sticky — resume! never flips it back to enabled' do
      expect(described_class.disable!(gateway)).to be(true)
      expect(described_class.state(gateway)).to eq('disabled')

      described_class.resume!(gateway)

      expect(described_class.state(gateway)).to eq('disabled')
      expect(gateway.reload.active).to be(false)
    end

    it 're-enables only through the explicit enable! action' do
      described_class.disable!(gateway)

      expect(described_class.enable!(gateway)).to be(true)
      expect(described_class.state(gateway)).to eq('enabled')
    end

    it 'is idempotent (no-op returns false)' do
      expect(described_class.enable!(gateway)).to be(false)
      described_class.disable!(gateway)
      expect(described_class.disable!(gateway)).to be(false)
    end

    it 'clears the breaker on resume! for a suspended provider' do
      described_class.suspend!(gateway, reason: 'auto', until_at: 1.hour.from_now)
      expect(described_class.state(gateway)).to eq('suspended')

      described_class.resume!(gateway)

      expect(described_class.state(gateway)).to eq('enabled')
    end
  end

  describe '三态优先级' do
    it 'prefers disabled over suspended' do
      described_class.suspend!(gateway, reason: 'auto', manual: true)
      gateway.update_columns(active: false)

      expect(described_class.state(gateway)).to eq('disabled')
    end

    it 'lists the effective option kinds' do
      make_optionized!(gateway, [
                         { 'kind' => 'card', 'active' => true, 'position' => 1 },
                         { 'kind' => 'google_pay', 'active' => false, 'position' => 2 }
                       ])

      expect(described_class.effective_kinds(gateway)).to eq(%w[card])
    end
  end
end
