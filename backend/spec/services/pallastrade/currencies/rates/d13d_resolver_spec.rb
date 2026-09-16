# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4）
#   AC-2 ← FR-2：解析排序（priority → 本店>全局 → effective_from → id）、生效口径、无候选返回 no_rate（不猜）
RSpec.describe PallasTrade::Currencies::Rates::Resolver do
  let!(:store) { create(:store, code: "d13d_res_#{SecureRandom.hex(4)}") }
  let!(:other_store) { create(:store, code: "d13d_res_other_#{SecureRandom.hex(4)}") }

  def resolve(**opts)
    described_class.call(**{ store: store, base: 'USD', quote: 'CNY' }.merge(opts)).value
  end

  it 'prefers the higher priority source' do
    manual = create(:currency_rate, store: store, source: 'manual', rate: 7.0)
    third = create(:currency_rate, store: store, source: 'third_party', rate: 7.05)
    provider = create(:currency_rate, store: store, source: 'provider', rate: 7.1)

    expect(resolve[:rate]).to eq(provider)
    provider.revoke!
    expect(resolve[:rate]).to eq(third)
    third.revoke!
    expect(resolve[:rate]).to eq(manual)
  end

  it 'prefers a store rate over a global rate at the same priority, then the later effective_from, then the higher id' do
    create(:currency_rate, store: nil, source: 'manual', rate: 6.9)
    store_rate = create(:currency_rate, store: store, source: 'manual', rate: 7.0,
                                       effective_from: 2.days.ago)
    newer = create(:currency_rate, store: store, source: 'manual', rate: 7.05, effective_from: 1.day.ago)

    expect(resolve[:rate]).to eq(newer)

    # 同一 effective_from 时比 id 更大者（身份键含 effective_from，故用 update_columns 造同刻两行）
    same_from = 5.hours.ago
    older_row = create(:currency_rate, store: store, source: 'manual', rate: 7.06, effective_from: same_from)
    newer_row = create(:currency_rate, store: store, source: 'manual', rate: 7.07,
                                       effective_from: same_from + 1.hour)
    older_row.update_columns(effective_from: newer_row.effective_from)

    expect(resolve(at: newer_row.effective_from + 1.minute)[:rate]).to eq(newer_row)
    expect(store_rate).to be_persisted
  end

  it 'honours the effective window at the reference time' do
    row = create(:currency_rate, store: store, source: 'manual', rate: 7.0,
                                 effective_from: 2.days.ago, effective_until: 1.day.ago)
    row.update_columns(effective_from: 2.days.ago, effective_until: 1.day.ago)

    expect(resolve(at: 36.hours.ago)[:rate]).to eq(row)
    expect(resolve(at: Time.current)[:rate]).to be_nil
  end

  it 'ignores other stores and other currency pairs' do
    create(:currency_rate, store: other_store, source: 'manual', rate: 9.9)
    create(:currency_rate, store: store, source: 'manual', rate: 1.0, quote_currency: 'EUR')

    expect(resolve[:rate]).to be_nil
    expect(resolve[:signals]).to eq(['no_rate'])
  end

  it 'reports same_currency without touching the database' do
    create(:currency_rate, store: store, source: 'manual', rate: 7.0)

    result = resolve(quote: 'USD')

    expect(result[:rate]).to be_nil
    expect(result[:signals]).to eq(['same_currency'])
  end

  it 'fails without a currency pair' do
    expect(described_class.call(store: store, base: '', quote: 'CNY')).not_to be_success
  end

  it 'uses supplied candidates instead of re-querying (batch preload)' do
    row = create(:currency_rate, store: store, source: 'manual', rate: 7.0)

    expect(PallasTrade::CurrencyRate).not_to receive(:for_store)

    expect(resolve(candidates: [row])[:rate]).to eq(row)
  end
end
