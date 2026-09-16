# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13c-fee-cost-report（D13 切片3）
#   AC-2 ← FR-2：解析优先级 method > provider > store > global；同优先级取更晚 effective_from；确定性
#   AC-3 ← FR-2：条件匹配（币种/卡类型/地区）；本地无法判定 → 不猜（skipped 留痕）
RSpec.describe PallasTrade::Payments::Fees::Resolver do
  let!(:store) { create(:store, code: "d13c_resolver_#{SecureRandom.hex(4)}") }
  let!(:other_store) { create(:store, code: "d13c_resolver_other_#{SecureRandom.hex(4)}") }
  let!(:payment_method) do
    create(:check_payment_method, store: store, active: true, display_on: 'both',
                                  name: "d13c-pm-#{SecureRandom.hex(3)}",
                                  metadata: { 'optionized' => true,
                                              'options' => [{ 'kind' => 'card', 'active' => true,
                                                              'position' => 0 }] })
  end

  def context(overrides = {})
    { store_id: store.id, store: store, payment_method_id: payment_method.id, method_key: 'card',
      currency: 'USD', card_type: 'visa', region: 'US', order_country: 'US' }.merge(overrides)
  end

  def resolve(overrides = {}, **options)
    described_class.call(context: context(overrides), **options).value
  end

  describe 'priority' do
    it 'picks the most specific scope' do
      global = create(:payment_fee_policy, store: store, name: 'global', scope_type: 'global')
      store_level = create(:payment_fee_policy, store: store, name: 'store', scope_type: 'store')
      provider = create(:payment_fee_policy, store: store, name: 'provider', scope_type: 'provider',
                                             scope_id: payment_method.id.to_s)
      method = create(:payment_fee_policy, store: store, name: 'method', scope_type: 'method', scope_id: 'card')

      expect(resolve[:policy]).to eq(method)
      method.revoke!
      expect(resolve[:policy]).to eq(provider)
      provider.revoke!
      expect(resolve[:policy]).to eq(store_level)
      store_level.revoke!
      expect(resolve[:policy]).to eq(global)
      global.revoke!
      expect(resolve[:policy]).to be_nil
    end

    it 'prefers the later effective_from within the same scope, then the higher id' do
      create(:payment_fee_policy, store: store, name: 'older', scope_type: 'global', effective_from: 3.days.ago)
      newer = create(:payment_fee_policy, store: store, name: 'newer', scope_type: 'global', effective_from: 1.day.ago)

      expect(resolve[:policy]).to eq(newer)

      same_from = 1.day.ago
      create(:payment_fee_policy, store: store, name: 'older-same-from', scope_type: 'global',
                                  effective_from: same_from)
      newest = create(:payment_fee_policy, store: store, name: 'newest-same-from', scope_type: 'global',
                                           effective_from: same_from)

      expect(resolve(at: newer.effective_from + 1.minute)[:policy]).to eq(newest)
    end

    it 'ignores policies of another store' do
      create(:payment_fee_policy, store: other_store, name: 'foreign', scope_type: 'store')

      expect(resolve[:policy]).to be_nil
    end

    it 'evaluates the effective window at the given reference time' do
      policy = create(:payment_fee_policy, store: store, name: 'windowed', scope_type: 'global',
                                           effective_from: 2.days.ago, effective_until: 1.day.ago)
      policy.update_columns(effective_from: 2.days.ago, effective_until: 1.day.ago)

      expect(resolve(at: 36.hours.ago)[:policy]).to eq(policy)
      expect(resolve(at: Time.current)[:policy]).to be_nil
    end
  end

  describe 'conditions' do
    it 'skips a policy whose conditions do not match and records the reason' do
      # 更具体的 method 策略币种不符 → 落到 provider
      create(:payment_fee_policy, store: store, name: 'eur', scope_type: 'method', scope_id: 'card',
                                  currency: 'EUR')
      provider = create(:payment_fee_policy, store: store, name: 'provider', scope_type: 'provider',
                                             scope_id: payment_method.id.to_s)

      result = resolve

      expect(result[:policy]).to eq(provider)
      expect(result[:skipped].map { |skip| skip[:reason] }).to include('currency_mismatch')
    end

    it 'never guesses a declared condition that local data cannot prove' do
      create(:payment_fee_policy, store: store, name: 'visa only', scope_type: 'global', card_type: 'visa')

      result = resolve({ card_type: nil })

      expect(result[:policy]).to be_nil
      expect(result[:skipped].first[:reason]).to eq('card_type_undetermined')
    end
  end

  describe 'context' do
    it 'derives the resolver context from a payment without inventing missing values' do
      order = create(:order_with_line_items, store: store, currency: 'USD', line_items_count: 1,
                                             line_items_price: 500, shipment_cost: 0)
      payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'completed',
                                 source: nil, skip_source_requirement: true)

      ctx = described_class::Context.from_payment(payment)

      expect(ctx.store_id).to eq(store.id)
      expect(ctx.payment_method_id).to eq(payment_method.id)
      expect(ctx.method_key).to eq('card')
      expect(ctx.currency).to eq('USD')
      expect(ctx.amount.to_d).to eq(100.to_d)
      expect(ctx.card_type).to be_nil
    end

    it 'skips region/card resolution when not requested (avoids N+1 queries)' do
      order = create(:order_with_line_items, store: store, currency: 'USD', line_items_count: 1,
                                             line_items_price: 500, shipment_cost: 0)
      payment = create(:payment, order: order, payment_method: payment_method, amount: 50, state: 'completed',
                                 source: nil, skip_source_requirement: true)

      ctx = described_class::Context.from_payment(payment, with_region: false, with_card_type: false)

      expect(ctx.region).to be_nil
      expect(ctx.card_type).to be_nil
    end
  end

  describe 'candidates preloading' do
    it 'uses supplied candidates instead of re-querying' do
      policy = create(:payment_fee_policy, store: store, name: 'preloaded', scope_type: 'global')
      candidates = [policy]

      expect(PallasTrade::PaymentFeePolicy).not_to receive(:for_store)

      expect(resolve(candidates: candidates)[:policy]).to eq(policy)
    end
  end
end
