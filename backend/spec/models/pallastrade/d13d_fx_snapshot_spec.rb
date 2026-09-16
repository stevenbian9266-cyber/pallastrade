# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4）
#   AC-5 ← FR-3：快照字段校验 / 一单一种币对唯一 / 偏差展示辅助 / 信号
RSpec.describe PallasTrade::FxSnapshot, type: :model do
  let!(:store) do
    create(:store, code: "d13d_snap_#{SecureRandom.hex(4)}", default_currency: 'USD',
                   supported_currencies: 'USD,CNY,EUR,GBP,JPY')
  end
  let!(:order) { create(:order, store: store, currency: 'CNY') }

  def build_snapshot(attrs = {})
    described_class.new(**{
      order: order, store: store, base_currency: 'USD', quote_currency: 'CNY',
      display_rate: 7.1, effective_rate: 7.1355, rate_source: 'manual', locked_at: Time.current
    }.merge(attrs))
  end

  it 'is valid with the required lock fields and defaults to pending' do
    snapshot = build_snapshot

    expect(snapshot).to be_valid
    expect(snapshot.variance_status).to eq('pending')
    expect(snapshot.compared?).to be(false)
    expect(snapshot.mismatched?).to be(false)
  end

  it 'rejects non-positive rates, unknown status and unknown settlement source' do
    expect(build_snapshot(display_rate: 0)).not_to be_valid
    expect(build_snapshot(effective_rate: -1)).not_to be_valid
    expect(build_snapshot(variance_status: 'maybe')).not_to be_valid
    expect(build_snapshot(settlement_source: 'guessed')).not_to be_valid
    expect(build_snapshot(up_charge_percent: -0.1)).not_to be_valid
  end

  it 'allows only one snapshot per order and currency pair' do
    create(:fx_snapshot, order: order, store: store, base_currency: 'USD', quote_currency: 'CNY')

    expect(build_snapshot.save).to be(false)
    expect(build_snapshot(effective_rate: 7.2, quote_currency: 'EUR', display_rate: 0.92)).to be_valid
  end

  describe 'scopes' do
    it 'separates awaiting-comparison from decided rows and isolates stores' do
      other_store = create(:store, code: "d13d_snap_other_#{SecureRandom.hex(4)}",
                                  supported_currencies: 'USD,CNY,EUR,JPY')
      pending = create(:fx_snapshot, order: order, store: store, base_currency: 'USD', quote_currency: 'CNY')
      matched_order = create(:order, store: store, currency: 'CNY')
      matched = create(:fx_snapshot, order: matched_order, store: store, base_currency: 'USD', quote_currency: 'EUR',
                                     display_rate: 0.92, effective_rate: 0.92, variance_status: 'matched',
                                     compared_at: Time.current)
      foreign_order = create(:order, store: other_store, currency: 'CNY')
      create(:fx_snapshot, order: foreign_order, store: other_store, base_currency: 'USD', quote_currency: 'JPY',
                           display_rate: 145, effective_rate: 145)

      expect(described_class.for_store(store).awaiting_comparison).to include(pending)
      expect(described_class.for_store(store).awaiting_comparison).not_to include(matched)
      expect(described_class.for_store(store).matched).to eq([matched])
      expect(described_class.for_store(store).count).to eq(2)
    end

    it 'filters by status and currency pair, and by lock period (left-closed, right-open)' do
      inside = create(:fx_snapshot, order: order, store: store, base_currency: 'USD', quote_currency: 'CNY',
                                    variance_status: 'mismatch', variance_bips: 120,
                                    locked_at: Time.zone.parse('2026-09-10 10:00:00'))

      expect(described_class.filter_by(store: store, variance_status: 'mismatch')).to eq([inside])
      expect(described_class.filter_by(store: store, base_currency: 'usd', quote_currency: 'cny')).to eq([inside])
      expect(described_class.for_store(store).locked_between(Time.zone.parse('2026-09-10'),
                                                            Time.zone.parse('2026-09-11'))).to include(inside)
      expect(described_class.for_store(store).locked_between(Time.zone.parse('2026-09-11'),
                                                            Time.zone.parse('2026-09-12'))).not_to include(inside)
    end
  end

  describe 'presentation helpers' do
    it 'converts bips to percent and tracks signals' do
      snapshot = create(:fx_snapshot, order: order, store: store, base_currency: 'USD', quote_currency: 'CNY',
                                      variance_status: 'mismatch', variance_bips: 125)

      expect(snapshot.variance_percent).to eq(BigDecimal('1.25'))
      snapshot.add_signal!('implied_rate')
      snapshot.add_signal!('implied_rate')
      expect(snapshot.reload.signal_list).to eq(['implied_rate'])
    end
  end
end
