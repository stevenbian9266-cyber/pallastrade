# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-health-trend-snapshot AC-001 AC-002 AC-003
#   AC-001 采集口径与 Issues.count 同源（逐项相等）
#   AC-002 同日重复采集幂等（不新增行、计数覆盖为当次值）
#   AC-003 按店隔离
RSpec.describe PallasTrade::CatalogHealth::Snapshot do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let(:store) { create(:store, code: "ch_snap_#{SecureRandom.hex(4)}", default: true) }
  let(:other_store) { create(:store, code: "ch_snap_other_#{SecureRandom.hex(4)}") }
  let(:on) { Date.current }

  before { PallasTrade::CatalogHealthSnapshot.delete_all }

  describe 'counting source of truth (AC-001)' do
    it 'stores exactly what Issues.count reports for every key' do
      create(:product, store: store, status: 'active', description: nil)

      described_class.capture(store, on: on)

      PallasTrade::CatalogHealth::Issues::KEYS.each do |key|
        record = PallasTrade::CatalogHealthSnapshot.find_by(store_id: store.id, issue_key: key, captured_on: on)

        expect(record).to be_present, "missing snapshot row for #{key}"
        expect(record.count).to eq(PallasTrade::CatalogHealth::Issues.count(store, key))
      end
    end

    # 计 0 也要留行：0 是事实（"这类问题没有了"），没有行是缺失（"还没采过"）。
    it 'writes a row for every key, including zeros' do
      described_class.capture(store, on: on)

      expect(PallasTrade::CatalogHealthSnapshot.where(store_id: store.id, captured_on: on).count)
        .to eq(PallasTrade::CatalogHealth::Issues::KEYS.size)
    end

    it 'returns the written rows' do
      expect(described_class.capture(store, on: on).size).to eq(PallasTrade::CatalogHealth::Issues::KEYS.size)
    end
  end

  describe 'idempotency (AC-002)' do
    it 'does not add rows when re-run on the same day' do
      described_class.capture(store, on: on)

      expect { described_class.capture(store, on: on) }
        .not_to change { PallasTrade::CatalogHealthSnapshot.where(store_id: store.id).count }
    end

    it 'overwrites the stored count with the latest truth' do
      described_class.capture(store, on: on)

      create(:product, store: store, status: 'active', description: nil)
      described_class.capture(store, on: on)

      record = PallasTrade::CatalogHealthSnapshot.find_by(
        store_id: store.id, issue_key: 'missing_description', captured_on: on
      )

      expect(record.count).to eq(PallasTrade::CatalogHealth::Issues.count(store, 'missing_description'))
    end
  end

  describe 'store isolation (AC-003)' do
    it 'never writes rows for another store' do
      other_store

      described_class.capture(store, on: on)

      expect(PallasTrade::CatalogHealthSnapshot.where(store_id: other_store.id)).to be_empty
    end
  end
end
