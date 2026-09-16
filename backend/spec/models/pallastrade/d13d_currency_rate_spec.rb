# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4）
#   AC-1 ← FR-1：汇率归一化（币种/来源/状态）、校验（rate>0、base≠quote、priority）、身份键幂等、位阶与生效口径
RSpec.describe PallasTrade::CurrencyRate, type: :model do
  let!(:store) { create(:store, code: "d13d_rate_#{SecureRandom.hex(4)}") }
  let!(:other_store) { create(:store, code: "d13d_rate_other_#{SecureRandom.hex(4)}") }

  def build_rate(attrs = {})
    PallasTrade::CurrencyRate.new(**{
      base_currency: 'USD', quote_currency: 'CNY', rate: 7.1,
      identity_key: SecureRandom.hex(32)
    }.merge(attrs))
  end

  describe 'normalization' do
    it 'upcases currencies, downcases source/status and keeps rate precision' do
      row = build_rate(base_currency: ' usd ', quote_currency: 'cny', source: 'PROVIDER', status: 'ACTIVE',
                       rate: '7.1234567891')
      row.identity_key = described_class.identity_key_for(base_currency: 'USD', quote_currency: 'CNY',
                                                          source: 'provider')

      expect(row).to be_valid
      expect(row.base_currency).to eq('USD')
      expect(row.quote_currency).to eq('CNY')
      expect(row.source).to eq('provider')
      expect(row.status).to eq('active')
      expect(row.rate.to_d).to eq(BigDecimal('7.1234567891'))
      expect(row.priority).to eq(30) # provider 默认优先级
    end

    it 'ignores blank note and invalid effective timestamps' do
      row = build_rate(note: '   ', effective_from: 'not-a-date')
      row.identity_key = described_class.identity_key_for(base_currency: 'USD', quote_currency: 'CNY',
                                                          source: 'manual')

      expect(row).to be_valid
      expect(row.note).to be_nil
      expect(row.effective_from).to be_nil
    end
  end

  describe 'validations' do
    it 'rejects non-positive rate, same currencies, unknown currency and negative priority' do
      base = { base_currency: 'USD', quote_currency: 'CNY', rate: 7.1 }

      expect(build_rate(base.merge(rate: 0))).not_to be_valid
      expect(build_rate(base.merge(quote_currency: 'USD'))).not_to be_valid
      expect(build_rate(base.merge(quote_currency: 'ZZZ'))).not_to be_valid
      expect(build_rate(base.merge(priority: -1))).not_to be_valid
      expect(build_rate(base.merge(source: 'friends'))).not_to be_valid
    end

    it 'rejects a duplicated identity key' do
      key = described_class.identity_key_for(base_currency: 'USD', quote_currency: 'CNY', source: 'manual')
      create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY', source: 'manual',
                             identity_key: key)

      expect(build_rate(identity_key: key)).not_to be_valid
    end
  end

  describe 'identity key' do
    it 'is stable for the same scope/pair/source/effective_from and differs per store scope' do
      stamp = Time.zone.parse('2026-09-01 00:00:00')
      store_key = described_class.identity_key_for(base_currency: 'usd', quote_currency: 'cny', source: 'manual',
                                                   effective_from: stamp, store: store)
      same = described_class.identity_key_for(base_currency: 'USD', quote_currency: 'CNY', source: 'manual',
                                              effective_from: stamp, store: store)
      global = described_class.identity_key_for(base_currency: 'USD', quote_currency: 'CNY', source: 'manual',
                                                effective_from: stamp, store: nil)

      expect(store_key).to eq(same)
      expect(store_key).not_to eq(global)
    end
  end

  describe 'scopes' do
    it 'keeps only active rows inside the effective window for the store scope' do
      active = create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY')
      future = create(:currency_rate, store: store, base_currency: 'EUR', quote_currency: 'CNY',
                                      effective_from: 1.day.from_now)
      expired = create(:currency_rate, store: store, base_currency: 'GBP', quote_currency: 'CNY',
                                       effective_until: 1.hour.ago)
      revoked = create(:currency_rate, store: store, base_currency: 'JPY', quote_currency: 'CNY')
      revoked.revoke!(actor: 'spec')
      foreign = create(:currency_rate, store: other_store, base_currency: 'AUD', quote_currency: 'CNY')
      global = create(:currency_rate, store: nil, base_currency: 'CAD', quote_currency: 'CNY')

      result = described_class.for_store(store).active.effective_at(Time.current)

      expect(result).to include(active, global)
      expect(result).not_to include(future, expired, revoked, foreign)
    end

    it 'orders by priority, then store over global, then recency then id' do
      global_manual = create(:currency_rate, store: nil, base_currency: 'USD', quote_currency: 'CNY',
                                             source: 'manual')
      store_manual = create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY',
                                            source: 'manual')
      third_party = create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY',
                                           source: 'third_party')
      provider = create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY',
                                        source: 'provider')

      ordered = described_class.by_priority.to_a

      expect(ordered.first).to eq(provider)
      expect(ordered.index(third_party)).to be < ordered.index(store_manual)
      expect(ordered.index(store_manual)).to be < ordered.index(global_manual)
    end
  end

  describe '#revoke! and #effective_rate_for' do
    it 'soft revokes with an audit trail' do
      row = create(:currency_rate, store: store)

      row.revoke!(actor: { type: 'PallasTrade::AdminUser', id: 9, label: 'ops@example.com' })

      row.reload
      expect(row.status).to eq('revoked')
      expect(row.revoked_at).to be_present
      expect(row.metadata['revoked_by']).to eq('ops@example.com')
    end

    it 'applies the up-charge markup to 10 decimals' do
      row = create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'EUR',
                                   rate: BigDecimal('0.9123456789'))

      expect(row.effective_rate_for(0)).to eq(BigDecimal('0.9123456789'))
      expect(row.effective_rate_for(0.5)).to eq(BigDecimal('0.9169074073'))
    end
  end
end
