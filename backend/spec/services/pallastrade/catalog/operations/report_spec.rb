# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-operations-report AC-001 AC-002 AC-003 AC-004 AC-005 AC-006（商品域审计 G-6）
#   AC-001 窗口过滤 / AC-002 批量 vs 单条 / AC-003 维护比率 / AC-004 操作者榜 /
#   AC-005 零写入 / AC-006 聚合在 DB 完成（查询数与行数无关）
RSpec.describe PallasTrade::Catalog::Operations::Report do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let(:store) { create(:store, code: "catalog_operations_#{SecureRandom.hex(4)}", default: true) }
  let(:now) { Time.zone.parse('2026-09-16 12:00:00') }
  let(:product_a) { create(:product, store: store) }
  let(:product_b) { create(:product, store: store) }

  # CI 的测试库由 db:prepare 种入数据，且 product 工厂本身会写审计/历史行。
  # 每个用例先清空审计表，让断言只面对本用例写入的条目（事务内，回滚安全）。
  before { PallasTrade::AuditLog.delete_all }

  def entry(product, action:, at: now, actor: 'alice@example.com', metadata: {})
    PallasTrade::AuditLog.create!(
      resource_type: 'PallasTrade::Product',
      resource_id: product.id,
      action: action,
      actor_label: actor,
      metadata: metadata.presence,
      occurred_at: at
    )
  end

  def report(window_days: 7)
    described_class.call(window_days: window_days, now: now).value
  end

  # AC-001：窗口外的条目不得计入任何数字。
  describe 'window filtering (AC-001)' do
    before do
      entry(product_a, action: 'product.updated')
      entry(product_b, action: 'product.updated', at: now - 10.days)
    end

    it 'counts only what happened inside the window' do
      result = report

      expect(result[:window_days]).to eq(7)
      expect(result[:totals][:entries]).to eq(1)
      expect(result[:totals][:products_touched]).to eq(1)
    end

    it 'widens to 30 days when asked' do
      result = report(window_days: 30)

      expect(result[:window_days]).to eq(30)
      expect(result[:totals][:entries]).to eq(2)
    end

    it 'falls back to the default for unknown windows' do
      expect(report(window_days: 365)[:window_days]).to eq(7)
      expect(report(window_days: 'nonsense')[:window_days]).to eq(7)
    end
  end

  # AC-002：批量与单条按**条目**的 metadata source 判定，而不是按 action 名。
  describe 'bulk vs single operations (AC-002)' do
    before do
      entry(product_a, action: 'product.bulk_price_updated', metadata: { 'source' => 'bulk' })
      entry(product_b, action: 'product.bulk_price_updated', metadata: { 'source' => 'bulk' })
      entry(product_a, action: 'product.updated', metadata: { 'changed' => ['name'] })
    end

    it 'separates entries by their source and reports covered products' do
      operations = report[:operations]

      expect(operations[:bulk][:entries]).to eq(2)
      expect(operations[:bulk][:products]).to eq(2)
      expect(operations[:single][:entries]).to eq(1)
      expect(operations[:single][:products]).to eq(1)
    end

    it 'keeps the per-action breakdown inside each side' do
      bulk_actions = report[:operations][:bulk][:actions]

      expect(bulk_actions.size).to eq(1)
      expect(bulk_actions.first).to include(action: 'product.bulk_price_updated', entries: 2, products: 2)
    end

    it 'counts the same action on both sides when only the entry says otherwise' do
      entry(product_b, action: 'product.updated', metadata: { 'changed' => ['status'] })

      operations = report[:operations]

      expect(operations[:single][:entries]).to eq(2)
      expect(operations[:bulk][:entries]).to eq(2)
    end
  end

  # AC-003：维护比率 = product.updated 条目数 ÷ 被动过的不同商品数；分母 0 → 0。
  describe 'maintenance ratio (AC-003)' do
    it 'returns 0 when nothing moved' do
      expect(report[:maintenance]).to eq(update_entries: 0, products_touched: 0, per_product: 0.0)
    end

    it 'divides update entries by touched products' do
      3.times { entry(product_a, action: 'product.updated') }
      entry(product_b, action: 'product.updated')
      entry(product_b, action: 'product.created')

      expect(report[:maintenance]).to eq(update_entries: 4, products_touched: 2, per_product: 2.0)
    end

    it 'ignores non-update actions in the numerator but not the denominator' do
      entry(product_a, action: 'product.created')
      entry(product_b, action: 'product.updated')

      expect(report[:maintenance]).to eq(update_entries: 1, products_touched: 2, per_product: 0.5)
    end
  end

  # AC-004：操作者榜按 entry 数降序；无 actor 归入 system（不得算成人）。
  describe 'actor leaderboard (AC-004)' do
    before do
      2.times { entry(product_a, action: 'product.updated', actor: 'alice@example.com') }
      entry(product_b, action: 'product.updated', actor: 'bob@example.com')
      entry(product_b, action: 'product.updated', actor: nil)
    end

    it 'ranks actors by entries and buckets anonymous writes under system' do
      expect(report[:actors]).to eq(
        [
          { actor: 'alice@example.com', entries: 2 },
          { actor: 'bob@example.com', entries: 1 },
          { actor: 'system', entries: 1 }
        ]
      )
    end
  end

  # AC-005：只读 —— 跑报表不产生任何审计条目。
  describe 'read-only guarantee (AC-005)' do
    before { entry(product_a, action: 'product.updated') }

    it 'never writes audit rows' do
      expect { report }.not_to change { PallasTrade::AuditLog.count }
    end
  end

  # AC-006：聚合在数据库完成 —— 查询数与窗口内行数无关。
  describe 'aggregation happens in the database (AC-006)' do
    it 'does not scale its query count with the number of entries' do
      entry(product_a, action: 'product.updated')
      small = count_queries { report }

      20.times { entry(product_b, action: 'product.updated') }
      large = count_queries { report }

      expect(large).to eq(small)
      expect(report[:totals][:entries]).to eq(21)
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

  # 口径声明（D-3）：审计表没有 store 维度 → 报表必须如实标注为全库口径，不得假装按店过滤。
  describe 'scope declaration' do
    it 'declares the report as all-stores' do
      expect(report[:scope_note]).to eq('all_stores')
    end
  end
end
