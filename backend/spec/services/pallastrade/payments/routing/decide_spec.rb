# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout 支付核心统一 · 切片 P3-A —— 方式级路由决策（硬门 + 排序 + 确定性）
#
#   硬门：配置了该方式 → 厂商三态 → 账户收窄 → Availability::Resolver（D8/D11/D15c 同源）
#   排序：策略优先序（市场覆写 > 全局）→ 入口 position → provider id（确定性兜底）
RSpec.describe PallasTrade::Payments::Routing::Decide do
  let!(:store) { create(:store, code: "p3a_routing_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'P3A Routing Store') }
  let(:order) { create(:order, store: store) }

  def provider!(name:, optionized: true, options: nil, **attrs)
    gateway = create(:stripe_gateway, store: store, name: name, **attrs)
    if optionized
      gateway.update_columns(private_metadata: {
                               'optionized' => true,
                               'options' => options || [{ 'kind' => 'card', 'active' => true, 'position' => 1 }]
                             })
      gateway.reload
    end
    gateway
  end

  def decide(method_key, policy: nil)
    described_class.call(order: order, method_key: method_key, policy: policy)
  end

  describe 'AC-1 硬门' do
    it 'answers no_candidate when no provider offers the method' do
      provider!(name: 'Stripe A')

      decision = decide('klarna')

      expect(decision['status']).to eq('no_candidate')
      expect(decision['chosen']).to be_nil
      expect(decision['rejected'].map { |entry| entry['reason'] }).to include('method_not_configured')
    end

    it 'rejects a disabled provider with the reason it was rejected for' do
      gateway = provider!(name: 'Stripe A')
      PallasTrade::Payments::Providers::State.disable!(gateway)

      decision = decide('card')

      expect(decision['status']).to eq('no_candidate')
      expect(decision['rejected'].map { |entry| entry['reason'] }).to include('provider_disabled')
    end

    it 'rejects a suspended (breaker open) provider' do
      gateway = provider!(name: 'Stripe A')
      PallasTrade::Payments::Providers::State.suspend!(gateway, kind: 'card', reason: 'down', manual: true)

      decision = decide('card')

      expect(decision['rejected'].map { |entry| entry['reason'] }).to include('provider_suspended')
    end

    it 'rejects a method the account has not opened' do
      gateway = provider!(name: 'Stripe A')
      gateway.update_columns(private_metadata: gateway.metadata.merge('account' => { 'methods' => %w[apple_pay] }))
      gateway.reload

      decision = decide('card')

      expect(decision['rejected'].map { |entry| entry['reason'] }).to include('account_not_opened')
    end
  end

  describe 'AC-2 排序' do
    it 'picks the only candidate and reports position as the basis' do
      gateway = provider!(name: 'Stripe A')

      decision = decide('card')

      expect(decision['status']).to eq('decided')
      expect(decision['chosen']['provider_id']).to eq(gateway.prefixed_id)
      expect(decision['chosen']['basis']).to eq('position')
      expect(decision['chosen']['rank']).to eq(1)
    end

    it 'lets a policy priority override pick the other provider' do
      first = provider!(name: 'Stripe A', options: [{ 'kind' => 'card', 'active' => true, 'position' => 1 }])
      second = provider!(name: 'Stripe B', options: [{ 'kind' => 'card', 'active' => true, 'position' => 2 }])
      policy = { 'mode' => 'priority_only', 'unsupported_mode' => false,
                 'priority' => { 'card' => [second.prefixed_id] }, 'markets' => {} }

      decision = decide('card', policy: policy)

      expect(decision['chosen']['provider_id']).to eq(second.prefixed_id)
      expect(decision['chosen']['basis']).to eq('priority_override')
      expect(decision['candidates'].map { |item| item['provider_id'] }).to eq([second.prefixed_id, first.prefixed_id])
    end

    it 'prefers the market override over the global priority' do
      policy = PallasTrade::Payments::Routing::Policy.normalize(
        'priority' => { 'card' => %w[pm_global] },
        'markets' => { '7' => { 'card' => %w[pm_market] } }
      )

      expect(PallasTrade::Payments::Routing::Policy.priority_sequence(policy, method_key: 'card', market_id: 7)).to eq(%w[pm_market])
      expect(PallasTrade::Payments::Routing::Policy.priority_sequence(policy, method_key: 'card', market_id: 9)).to eq(%w[pm_global])
      expect(PallasTrade::Payments::Routing::Policy.priority_sequence(policy, method_key: 'apple_pay', market_id: 7)).to eq([])
    end

    it 'is deterministic for identical inputs' do
      provider!(name: 'Stripe A')
      provider!(name: 'Stripe B')

      first = decide('card')
      second = decide('card')

      expect(first['chosen']).to eq(second['chosen'])
      expect(first['candidates']).to eq(second['candidates'])
    end
  end

  describe 'AC-3 模式与诚实性' do
    it 'does not apply routing in off / shadow mode' do
      provider!(name: 'Stripe A')

      expect(decide('card', policy: { 'mode' => 'off', 'unsupported_mode' => false, 'priority' => {}, 'markets' => {} })['applied']).to be(false)
      expect(decide('card', policy: { 'mode' => 'shadow', 'unsupported_mode' => false, 'priority' => {}, 'markets' => {} })['applied']).to be(false)
      expect(decide('card', policy: { 'mode' => 'priority_only', 'unsupported_mode' => false, 'priority' => {}, 'markets' => {} })['applied']).to be(true)
    end

    it 'normalizes an unimplemented mode to off instead of pretending to rank by cost' do
      policy = PallasTrade::Payments::Routing::Policy.normalize('mode' => 'priority_cost')

      expect(policy['mode']).to eq('off')
      expect(policy['unsupported_mode']).to be(true)
    end

    it 'never reads or writes money records' do
      provider!(name: 'Stripe A')
      before_counts = [PallasTrade::Payment.count, PallasTrade::PaymentSession.count]

      decide('card')

      expect([PallasTrade::Payment.count, PallasTrade::PaymentSession.count]).to eq(before_counts)
    end
  end
end
