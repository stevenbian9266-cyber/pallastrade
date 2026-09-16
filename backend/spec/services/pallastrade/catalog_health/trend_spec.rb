# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-health-trend-snapshot AC-004 AC-005
#   AC-004 差值 = 当前 − 窗口内最早可用快照；方向按符号映射
#   AC-005 无/单条快照时为 unknown、差值为 nil（不编造 0 或"持平"）
RSpec.describe PallasTrade::CatalogHealth::Trend do
  let(:store) { create(:store, code: "ch_trend_#{SecureRandom.hex(4)}", default: true) }
  let(:today) { Date.current }

  before { PallasTrade::CatalogHealthSnapshot.delete_all }

  def snapshot(key:, count:, date:)
    PallasTrade::CatalogHealthSnapshot.create!(
      store_id: store.id, issue_key: key, captured_on: date, count: count
    )
  end

  def row_for(key, days: described_class::DEFAULT_DAYS)
    described_class.call(store, days: days, on: today).row_for(key)
  end

  describe 'delta and direction (AC-004)' do
    it 'reads a falling count as improvement' do
      snapshot(key: 'missing_description', count: 40, date: today - 5)
      snapshot(key: 'missing_description', count: 12, date: today)

      row = row_for('missing_description')

      expect(row.baseline).to eq(40)
      expect(row.current).to eq(12)
      expect(row.delta).to eq(-28)
      expect(row.direction).to eq(:improving)
      expect(row).to be_improving
    end

    it 'reads a rising count as worsening' do
      snapshot(key: 'missing_seo', count: 3, date: today - 3)
      snapshot(key: 'missing_seo', count: 9, date: today)

      expect(row_for('missing_seo').direction).to eq(:worsening)
      expect(row_for('missing_seo').delta).to eq(6)
    end

    it 'reads an unchanged count as flat' do
      snapshot(key: 'old_drafts', count: 5, date: today - 2)
      snapshot(key: 'old_drafts', count: 5, date: today)

      row = row_for('old_drafts')

      expect(row.direction).to eq(:flat)
      expect(row.delta).to eq(0)
    end

    # 基准点是窗口内最早可用快照：窗口外的旧数据不得污染"这轮治理"的判断。
    it 'ignores snapshots that fall outside the window' do
      snapshot(key: 'missing_media', count: 99, date: today - 90)
      snapshot(key: 'missing_media', count: 10, date: today - 3)
      snapshot(key: 'missing_media', count: 4, date: today)

      row = row_for('missing_media', days: 30)

      expect(row.baseline).to eq(10)
      expect(row.delta).to eq(-6)
    end

    it 'sums the net change across comparable issues' do
      snapshot(key: 'missing_description', count: 10, date: today - 1)
      snapshot(key: 'missing_description', count: 4, date: today)
      snapshot(key: 'missing_seo', count: 2, date: today - 1)
      snapshot(key: 'missing_seo', count: 5, date: today)

      expect(described_class.call(store, on: today).total_delta).to eq(-3)
    end
  end

  describe 'honest unknown (AC-005)' do
    it 'is unknown when there is no snapshot at all' do
      row = row_for('missing_translations')

      expect(row).to be_unknown
      expect(row.delta).to be_nil
      expect(row.current).to be_nil
      expect(row.points).to eq([])
    end

    # 只有一条快照 = 没有两个可比时点 → "变化"这件事不存在，显示"持平 0"就是编造。
    it 'is unknown with a single snapshot' do
      snapshot(key: 'missing_description', count: 7, date: today)

      expect(row_for('missing_description')).to be_unknown
    end

    it 'reports the whole window as empty and total_delta as nil' do
      trend = described_class.call(store, on: today)

      expect(trend).to be_empty
      expect(trend.total_delta).to be_nil
    end

    it 'covers every issue key even when nothing is comparable' do
      trend = described_class.call(store, on: today)

      expect(trend.rows.map(&:key)).to eq(PallasTrade::CatalogHealth::Issues::KEYS)
    end
  end

  describe 'window bounds' do
    it 'includes both ends of the window' do
      snapshot(key: 'missing_description', count: 1, date: today - 29)
      snapshot(key: 'missing_description', count: 5, date: today)

      row = row_for('missing_description', days: 30)

      expect(row.baseline).to eq(1)
      expect(row.delta).to eq(4)
    end

    it 'falls back to the default window for nonsense inputs' do
      expect(described_class.call(store, days: 0, on: today).days).to eq(described_class::DEFAULT_DAYS)
      expect(described_class.call(store, days: 'x', on: today).days).to eq(described_class::DEFAULT_DAYS)
    end

    # 查询数不随天数增长：一次取回窗口内全部快照，再在内存分组。
    it 'keeps its query count flat as the window fills up' do
      snapshot(key: 'missing_description', count: 1, date: today - 1)
      snapshot(key: 'missing_description', count: 2, date: today)
      small = count_queries { described_class.call(store, on: today).rows }

      # 让窗口内的行数成倍增长：不同 issue × 不同日期（同日同 issue 受唯一索引约束，只有一行）
      PallasTrade::CatalogHealth::Issues::KEYS.each_with_index do |key, index|
        snapshot(key: key, count: index, date: today - 10)
        snapshot(key: key, count: index + 1, date: today - 3)
      end
      large = count_queries { described_class.call(store, on: today).rows }

      expect(PallasTrade::CatalogHealthSnapshot.where(store_id: store.id).count).to be > 2
      expect(large).to eq(small)
    end

    def count_queries
      count = 0
      counter = lambda do |*_args, payload|
        count += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])
      end

      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }

      count
    end
  end
end
