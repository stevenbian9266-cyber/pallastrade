# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-health-trend-snapshot AC-007
#   AC-007 采集作业：遍历店铺、单店失败被捕获不影响其他店、作业本身不抛出
RSpec.describe PallasTrade::CatalogHealth::SnapshotSweeperJob do
  let(:good_store) { create(:store, code: "ch_job_good_#{SecureRandom.hex(4)}", default: true) }
  let(:bad_store) { create(:store, code: "ch_job_bad_#{SecureRandom.hex(4)}") }

  before { PallasTrade::CatalogHealthSnapshot.delete_all }

  describe 'capture sweep (AC-007)' do
    it 'captures stores and reports a summary' do
      good_store

      result = described_class.new.perform(store_limit: 500)

      expect(result[:stores_captured]).to be >= 1
      expect(result[:rows_written]).to be >= PallasTrade::CatalogHealth::Issues::KEYS.size
      expect(result[:captured_on]).to eq(Date.current.to_s)
    end

    # 一个店的判定 SQL 出错不该让其余店当天没有数据（趋势断档比噪声更糟）。
    it 'isolates a failing store instead of aborting the sweep' do
      good_store
      bad_store

      allow(PallasTrade::CatalogHealth::Snapshot).to receive(:capture).and_call_original
      allow(PallasTrade::CatalogHealth::Snapshot).to receive(:capture)
        .with(bad_store, on: Date.current)
        .and_raise(StandardError.new('boom'))

      result = nil
      expect { result = described_class.new.perform }.not_to raise_error

      expect(result[:stores_failed].map { |f| f[:store_id] }).to include(bad_store.id)
      expect(result[:stores_captured]).to be >= 1
    end

    it 'honours the store limit' do
      3.times { create(:store, code: "ch_job_lim_#{SecureRandom.hex(4)}") }

      result = described_class.new.perform(store_limit: 1)

      expect(result[:stores_captured]).to be <= 1
    end

    it 'accepts an explicit snapshot date so a missed day can be backfilled' do
      good_store

      described_class.new.perform(on: '2026-09-01')

      expect(
        PallasTrade::CatalogHealthSnapshot.where(store_id: good_store.id, captured_on: Date.new(2026, 9, 1)).count
      ).to eq(PallasTrade::CatalogHealth::Issues::KEYS.size)
    end

    it 'falls back to today for an unparseable date' do
      good_store

      expect(described_class.new.perform(on: 'not-a-date')[:captured_on]).to eq(Date.current.to_s)
    end

    # 采集只写快照表：不得在同一个店上产生重复行（幂等由唯一索引兜底）。
    it 'is idempotent when run twice on the same day' do
      good_store

      described_class.new.perform
      expect { described_class.new.perform }
        .not_to change { PallasTrade::CatalogHealthSnapshot.where(store_id: good_store.id).count }
    end
  end
end
