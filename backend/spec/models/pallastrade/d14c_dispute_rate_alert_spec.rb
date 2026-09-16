# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14c-dispute-rate-board AC-006（台账唯一键幂等 + 档位语义 + 展示口径）
RSpec.describe PallasTrade::DisputeRateAlert, type: :model do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) { create(:store, code: "d14c_alert_#{suffix}", default_currency: 'USD') }

  # AC-006（幂等键 = 店铺 × 组织 × 评估日；同一评估日重复评估不会产生第二行）
  describe 'dedupe key' do
    it 'builds a stable key and rejects a duplicate row' do
      key = described_class.key_for(store_id: store.id, network: 'visa', evaluated_on: Date.new(2026, 9, 16))

      expect(key).to eq("rate:#{store.id}:visa:2026-09-16")

      create(:dispute_rate_alert, store: store, network: 'visa', evaluated_on: Date.new(2026, 9, 16))

      duplicate = build(:dispute_rate_alert, store: store, network: 'visa', evaluated_on: Date.new(2026, 9, 16))
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:dedupe_key]).to be_present
    end

    it 'accepts a Time and normalizes it to a date' do
      key = described_class.key_for(store_id: store.id, network: 'master',
                                    evaluated_on: Time.zone.parse('2026-09-16 23:30'))

      expect(key).to eq("rate:#{store.id}:master:2026-09-16")
    end
  end

  # AC-006
  describe 'validations' do
    it 'only accepts the two alert tiers' do
      alert = build(:dispute_rate_alert, store: store, tier: 'ok')

      expect(alert).not_to be_valid
      expect(alert.errors[:tier]).to be_present
    end

    it 'requires a positive window' do
      alert = build(:dispute_rate_alert, store: store, window_days: 0)

      expect(alert).not_to be_valid
    end
  end

  # AC-007
  describe 'tier helpers' do
    it 'reports tier, triggered metrics and escalation' do
      alert = create(:dispute_rate_alert, store: store, network: 'visa', tier: described_class::BREACHED,
                                          triggered_metrics: %w[count amount], escalated_at: Time.current)

      expect(alert.breached?).to be(true)
      expect(alert.approaching?).to be(false)
      expect(alert.triggered).to contain_exactly('count', 'amount')
      expect(alert.triggered?('count')).to be(true)
      expect(alert.triggered?('amount')).to be(true)
      expect(alert.escalated?).to be(true)
    end

    it 'ignores junk inside triggered_metrics' do
      alert = create(:dispute_rate_alert, store: store, network: 'visa', triggered_metrics: ['count', 'nope', nil])

      expect(alert.triggered).to eq(['count'])
    end

    it 'converts bps into percentages and usage without faking missing values' do
      alert = create(:dispute_rate_alert, store: store, network: 'visa', count_ratio_bps: 65,
                                          count_threshold_bps: 80, amount_ratio_bps: nil,
                                          amount_threshold_bps: nil)

      expect(alert.count_ratio_percent).to eq(BigDecimal('0.65'))
      expect(alert.count_threshold_percent).to eq(BigDecimal('0.8'))
      expect(alert.usage_percent('count')).to eq(81.3)
      expect(alert.amount_ratio_percent).to be_nil
      expect(alert.usage_percent('amount')).to be_nil
    end
  end

  # AC-012（筛选口径：页面计数与列表共用）
  describe '.filter_by' do
    it 'filters by store, network, tier and evaluation date' do
      other_store = create(:store, code: "d14c_alert_other_#{suffix}")
      mine = create(:dispute_rate_alert, store: store, network: 'visa', tier: described_class::APPROACHING,
                                         evaluated_on: Date.new(2026, 9, 10))
      create(:dispute_rate_alert, store: store, network: 'master', tier: described_class::BREACHED,
                                  evaluated_on: Date.new(2026, 9, 12))
      create(:dispute_rate_alert, store: other_store, network: 'visa', tier: described_class::APPROACHING,
                                  evaluated_on: Date.new(2026, 9, 11))

      expect(described_class.filter_by(store_id: store.id).count).to eq(2)
      expect(described_class.filter_by(store_id: store.id, network: 'visa').pluck(:id)).to eq([mine.id])
      expect(described_class.filter_by(store_id: store.id, tier: described_class::BREACHED).count).to eq(1)
      expect(described_class.filter_by(store_id: store.id, from: Date.new(2026, 9, 11)).count).to eq(1)
      expect(described_class.filter_by(store_id: store.id, to: Date.new(2026, 9, 10)).pluck(:id)).to eq([mine.id])
      expect(described_class.for_store(store).recent_first.first.evaluated_on).to eq(Date.new(2026, 9, 12))
    end
  end
end
