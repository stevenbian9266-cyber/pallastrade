# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout 支付核心统一 · 切片 P3-B —— 策略写入原语 + 无订单上下文预览
#
#   写入：白名单（mode ∈ 已实现模式 / priority 目标 ∈ 本店 provider / markets 键 ∈ 本店市场）+ 幂等 + 零资金副作用
#   预览：复用 Decide 的候选装配与排序，跳过订单级闸门并**显式标记** order_gates=skipped
RSpec.describe 'Payment routing policy write + preview' do
  let!(:store) { create(:store, code: "p3b_routing_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'P3B Routing Store') }

  def provider!(name:, position: 1)
    gateway = create(:stripe_gateway, store: store, name: name)
    gateway.update_columns(private_metadata: {
                             'optionized' => true,
                             'options' => [{ 'kind' => 'card', 'active' => true, 'position' => position }]
                           })
    gateway.reload
  end

  describe 'AC-1 策略写入' do
    it 'persists a normalized policy and reads it back' do
      gateway = provider!(name: 'Stripe A')

      outcome = PallasTrade::Payments::Routing::Policy.write!(
        store, mode: 'priority_only', priority: { 'card' => [gateway.prefixed_id] }, actor: 'admin@example.com'
      )

      expect(outcome['unchanged']).to be(false)
      policy = PallasTrade::Payments::Routing::Policy.for_store(store)
      expect(policy['mode']).to eq('priority_only')
      expect(policy['priority']['card']).to eq([gateway.prefixed_id])
      expect(store.reload.private_metadata['payment_routing']['updated_by']).to eq('admin@example.com')
    end

    it 'rejects an unimplemented mode instead of storing it' do
      outcome = PallasTrade::Payments::Routing::Policy.write!(store, mode: 'priority_cost')

      expect(outcome['rejected']['mode']).to eq(['priority_cost'])
      expect(PallasTrade::Payments::Routing::Policy.for_store(store)['mode']).to eq('off')
    end

    it 'rejects a provider that does not belong to the store' do
      provider!(name: 'Stripe A')

      outcome = PallasTrade::Payments::Routing::Policy.write!(store, priority: { 'card' => %w[pm_unknown] })

      expect(outcome['rejected']['priority']['card']).to eq(%w[pm_unknown])
      expect(PallasTrade::Payments::Routing::Policy.for_store(store)['priority']).to eq({})
    end

    it 'rejects a market key that does not belong to the store' do
      gateway = provider!(name: 'Stripe A')

      outcome = PallasTrade::Payments::Routing::Policy.write!(
        store, markets: { '999999' => { 'card' => [gateway.prefixed_id] } }
      )

      expect(outcome['rejected']['markets']).to eq(%w[999999])
    end

    it 'is idempotent and never touches money records' do
      gateway = provider!(name: 'Stripe A')
      PallasTrade::Payments::Routing::Policy.write!(store, mode: 'shadow', priority: { 'card' => [gateway.prefixed_id] })
      stamp = store.reload.private_metadata['payment_routing']['updated_at']
      before_counts = [PallasTrade::Payment.count, PallasTrade::PaymentSession.count]

      outcome = PallasTrade::Payments::Routing::Policy.write!(
        store, mode: 'shadow', priority: { 'card' => [gateway.prefixed_id] }
      )

      expect(outcome['unchanged']).to be(true)
      expect(store.reload.private_metadata['payment_routing']['updated_at']).to eq(stamp)
      expect([PallasTrade::Payment.count, PallasTrade::PaymentSession.count]).to eq(before_counts)
    end
  end

  describe 'AC-2 无订单上下文预览' do
    it 'marks the preview as skipping order-scoped gates and ranks by policy priority' do
      first = provider!(name: 'Stripe A', position: 1)
      second = provider!(name: 'Stripe B', position: 2)
      PallasTrade::Payments::Routing::Policy.write!(
        store, mode: 'priority_only', priority: { 'card' => [second.prefixed_id] }
      )

      summary = PallasTrade::Payments::Routing::Summary.for_store(store)

      expect(summary['order_gates']).to eq('skipped')
      expect(summary['applied']).to be(true)
      expect(summary['methods']['card']['status']).to eq('preview')
      expect(summary['methods']['card']['chosen']['provider_id']).to eq(second.prefixed_id)
      expect(summary['methods']['card']['chosen']['basis']).to eq('priority_override')
      expect(summary['methods']['card']['candidates'].map { |item| item['provider_id'] }).to eq([second.prefixed_id, first.prefixed_id])
    end

    it 'reports a disabled provider as rejected rather than silently dropping it' do
      gateway = provider!(name: 'Stripe A')
      PallasTrade::Payments::Providers::State.disable!(gateway)

      summary = PallasTrade::Payments::Routing::Summary.for_store(store)

      expect(summary['methods']['card']['status']).to eq('no_candidate')
      expect(summary['methods']['card']['rejected'].map { |entry| entry['reason'] }).to eq(['provider_disabled'])
    end

    it 'lists every method the store claims and never invents one' do
      provider!(name: 'Stripe A')

      summary = PallasTrade::Payments::Routing::Summary.for_store(store)

      expect(summary['methods'].keys).to eq(['card'])
    end

    it 'has zero money side effects' do
      provider!(name: 'Stripe A')
      before_counts = [PallasTrade::Payment.count, PallasTrade::PaymentSession.count]

      PallasTrade::Payments::Routing::Summary.for_store(store)

      expect([PallasTrade::Payment.count, PallasTrade::PaymentSession.count]).to eq(before_counts)
    end
  end
end
