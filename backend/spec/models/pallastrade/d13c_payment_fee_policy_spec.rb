# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13c-fee-cost-report（D13 切片3）
#   AC-1 ← FR-1：费率策略归一化 / 校验 / 生效窗口 / 店铺隔离 / 优先级 / 条件匹配 / 软撤销
RSpec.describe PallasTrade::PaymentFeePolicy, type: :model do
  let!(:store) { create(:store, code: "d13c_model_#{SecureRandom.hex(4)}") }
  let!(:other_store) { create(:store, code: "d13c_model_other_#{SecureRandom.hex(4)}") }

  def build_policy(attrs = {})
    described_class.new({ store: store, name: 'Default', scope_type: 'global' }.merge(attrs))
  end

  describe 'normalization' do
    it 'strips blanks to nil and normalizes case-insensitive fields' do
      policy = build_policy(
        name: '  Card rate  ',
        scope_type: 'provider',
        scope_id: '  42 ',
        currency: 'usd',
        card_type: 'VISA',
        region: 'jp',
        home_country: 'us',
        settlement_currency: 'eur',
        percent_fee: '2.9'
      )

      expect(policy).to be_valid
      expect(policy.name).to eq('Card rate')
      expect(policy.scope_id).to eq('42')
      expect(policy.currency).to eq('USD')
      expect(policy.card_type).to eq('visa')
      expect(policy.region).to eq('JP')
      expect(policy.home_country).to eq('US')
      expect(policy.settlement_currency).to eq('EUR')
      expect(policy.percent_fee.to_d).to eq(2.9.to_d)
      expect(policy.status).to eq('active')
    end

    it 'blank conditions become nil (= all)' do
      policy = build_policy(currency: '   ', card_type: '', region: nil)

      expect(policy).to be_valid
      expect(policy.currency).to be_nil
      expect(policy.card_type).to be_nil
      expect(policy.region).to be_nil
    end
  end

  describe 'validations' do
    it 'rejects percentages above 100 and negative amounts' do
      expect(build_policy(percent_fee: 120)).not_to be_valid
      expect(build_policy(platform_percent: -1)).not_to be_valid
      expect(build_policy(fixed_fee: -0.01)).not_to be_valid
      expect(build_policy(percent_fee: 100)).to be_valid
      expect(build_policy(percent_fee: 0)).to be_valid
    end

    it 'rejects min greater than max' do
      policy = build_policy(min_fee: 5, max_fee: 1)

      expect(policy).not_to be_valid
      expect(policy.errors[:min_fee]).to be_present
    end

    it 'requires scope_id for provider/method and normalizes it away for global/store' do
      expect(build_policy(scope_type: 'provider')).not_to be_valid
      expect(build_policy(scope_type: 'method', scope_id: 'card')).to be_valid

      global = build_policy(scope_type: 'global', scope_id: 'x')
      store_level = build_policy(scope_type: 'store', scope_id: 'x')

      expect(global).to be_valid
      expect(global.scope_id).to be_nil
      expect(store_level).to be_valid
      expect(store_level.scope_id).to be_nil
    end

    it 'rejects an unknown scope type and an empty name' do
      expect(build_policy(scope_type: 'planet')).not_to be_valid
      expect(build_policy(name: '  ')).not_to be_valid
    end
  end

  describe 'scopes' do
    it 'keeps only active policies inside their effective window' do
      active = create(:payment_fee_policy, store: store, name: 'active')
      not_yet = create(:payment_fee_policy, store: store, name: 'future', effective_from: 1.day.from_now)
      expired = create(:payment_fee_policy, store: store, name: 'expired', effective_until: 1.hour.ago)
      revoked = create(:payment_fee_policy, store: store, name: 'revoked')
      revoked.revoke!(actor: 'spec')

      result = described_class.for_store(store).active.effective_at(Time.current)

      expect(result).to include(active)
      expect(result).not_to include(not_yet, expired, revoked)
    end

    it 'isolates stores (global + own only)' do
      global = create(:payment_fee_policy, store: nil, name: 'global')
      own = create(:payment_fee_policy, store: store, name: 'own')
      foreign = create(:payment_fee_policy, store: other_store, name: 'foreign')

      result = described_class.for_store(store)

      expect(result).to include(global, own)
      expect(result).not_to include(foreign)
    end

    it 'orders candidates by specificity then recency then id' do
      global = create(:payment_fee_policy, store: store, name: 'global', scope_type: 'global')
      store_level = create(:payment_fee_policy, store: store, name: 'store level', scope_type: 'store')
      provider = create(:payment_fee_policy, store: store, name: 'provider', scope_type: 'provider', scope_id: '7')
      older_method = create(:payment_fee_policy, store: store, name: 'method old', scope_type: 'method',
                                                  scope_id: 'card', effective_from: 2.days.ago)
      newer_method = create(:payment_fee_policy, store: store, name: 'method new', scope_type: 'method',
                                                  scope_id: 'card', effective_from: 1.day.ago)

      ordered = described_class.for_store(store).by_priority.to_a

      expect(ordered.index(newer_method)).to be < ordered.index(older_method)
      expect(ordered.index(older_method)).to be < ordered.index(provider)
      expect(ordered.index(provider)).to be < ordered.index(store_level)
      expect(ordered.index(store_level)).to be < ordered.index(global)
    end
  end

  describe '#matches_context?' do
    let(:context) do
      { store_id: store.id, payment_method_id: 42, method_key: 'card', currency: 'USD', card_type: 'visa', region: 'JP' }
    end

    it 'matches a global policy regardless of the context' do
      policy = create(:payment_fee_policy, store: store, name: 'global', scope_type: 'global')

      expect(policy.matches_context?(context)).to eq([true, []])
    end

    it 'matches provider / method scopes only on the exact target' do
      provider = create(:payment_fee_policy, store: store, name: 'provider', scope_type: 'provider', scope_id: '42')
      other = create(:payment_fee_policy, store: store, name: 'other provider', scope_type: 'provider', scope_id: '43')
      method = create(:payment_fee_policy, store: store, name: 'method', scope_type: 'method', scope_id: 'card')

      expect(provider.matches_context?(context).first).to be(true)
      expect(method.matches_context?(context).first).to be(true)
      expect(other.matches_context?(context)).to eq([false, ['scope_mismatch']])
    end

    it 'checks conditions and reports the reason' do
      currency = create(:payment_fee_policy, store: store, name: 'eur only', currency: 'EUR')
      card = create(:payment_fee_policy, store: store, name: 'visa only', card_type: 'visa')
      region = create(:payment_fee_policy, store: store, name: 'jp only', region: 'JP')

      expect(currency.matches_context?(context)).to eq([false, ['currency_mismatch']])
      expect(card.matches_context?(context).first).to be(true)
      expect(region.matches_context?(context).first).to be(true)
    end

    it 'never guesses when the local data cannot prove a declared condition' do
      card = create(:payment_fee_policy, store: store, name: 'visa only', card_type: 'visa')
      region = create(:payment_fee_policy, store: store, name: 'jp only', region: 'JP')
      blind = context.merge(card_type: nil, region: nil)

      expect(card.matches_context?(blind)).to eq([false, ['card_type_undetermined']])
      expect(region.matches_context?(blind)).to eq([false, ['region_undetermined']])
    end

    it 'does not match a store-scoped policy of another store' do
      foreign = create(:payment_fee_policy, store: other_store, name: 'foreign', scope_type: 'store')

      expect(foreign.matches_context?(context)).to eq([false, ['scope_mismatch']])
    end
  end

  describe '#revoke!' do
    it 'soft revokes and keeps the row with an audit trail' do
      policy = create(:payment_fee_policy, store: store, name: 'revokable')

      policy.revoke!(actor: { type: 'PallasTrade::AdminUser', id: 1, label: 'ops@example.com' })

      policy.reload
      expect(policy.status).to eq('revoked')
      expect(policy.revoked_at).to be_present
      expect(policy.metadata['revoked_by']).to eq('ops@example.com')
      expect(described_class.for_store(store).active).not_to include(policy)
    end
  end

  describe '#description' do
    it 'summarizes the declared components' do
      policy = build_policy(name: 'full', percent_fee: 2.9, fixed_fee: 0.3, platform_percent: 0.5,
                            cross_border_percent: 1, cross_border_fixed: 0.2, currency_conversion_percent: 0.75)

      expect(policy.description).to include('2.9%', '+0.3', 'platform 0.5%', 'cross-border 1.0%', 'fx 0.75%')
    end
  end
end
