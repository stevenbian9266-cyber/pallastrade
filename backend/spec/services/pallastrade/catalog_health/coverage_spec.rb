# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-health-coverage-ratios AC-001 AC-002 AC-003 AC-004 AC-005 AC-007 AC-010
#   AC-001 SEO 分母 = 未归档商品数
#   AC-002 翻译分母 = 商品数 × 支持语言数（与分子同单位）
#   AC-003 分母为 0 时比率为 nil（不出现 0.0 / NaN）
#   AC-004 无其它支持语言时翻译比率为 nil（不是 100%）
#   AC-005 分子与 Issues.count 严格相等
#   AC-007 零写入
#   AC-010 归档商品不计入分母
RSpec.describe PallasTrade::CatalogHealth::Coverage do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let(:store) do
    create(:store, code: "ch_cov_#{SecureRandom.hex(4)}", default: true,
                   default_locale: 'en', supported_locales: 'en,de,fr')
  end

  def coverage
    described_class.call(store)
  end

  describe 'molecule comes from the single counting authority (AC-005)' do
    it 'reports exactly what Issues.count reports' do
      create(:product, store: store, status: 'active')

      expect(coverage.metric_for('missing_seo').missing)
        .to eq(PallasTrade::CatalogHealth::Issues.count(store, 'missing_seo'))
      expect(coverage.metric_for('missing_translations').missing)
        .to eq(PallasTrade::CatalogHealth::Issues.count(store, 'missing_translations'))
    end
  end

  # D1 是本批的核心：两个比率**不能共用分母**。
  # SEO 数的是商品，翻译数的是 (商品 × 语言) —— 共用一个分母会算出一个错的比率，
  # 而且错得很像对的。这里构造一个让两个分母**必定不等**的场景来守住它。
  describe 'each ratio has its own denominator (AC-001 AC-002)' do
    before { 4.times { create(:product, store: store, status: 'active') } }

    it 'divides SEO by the product count' do
      metric = coverage.metric_for('missing_seo')

      expect(metric.total).to eq(4)
      expect(metric.missing_ratio).to eq(metric.missing.to_f / 4)
    end

    it 'divides translations by product count times supported locales' do
      # supported_locales = en,de,fr 且 default = en → 2 个"其它语言"
      metric = coverage.metric_for('missing_translations')

      expect(metric.total).to eq(4 * 2)
      expect(metric.total).not_to eq(4), '翻译分母不得退化成商品数（那会与 SEO 共用分母）'
    end

    it 'keeps coverage_ratio as the complement of missing_ratio' do
      metric = coverage.metric_for('missing_seo')

      expect(metric.coverage_ratio + metric.missing_ratio).to be_within(1e-9).of(1.0)
      expect(metric.coverage_percentage).to eq((metric.coverage_ratio * 100).round(1))
    end
  end

  describe 'archived products stay out of the denominator (AC-010)' do
    it 'counts only not-archived products' do
      create(:product, store: store, status: 'active')
      create(:product, store: store, status: 'archived')

      expect(coverage.metric_for('missing_seo').total).to eq(1)
    end
  end

  describe 'honest absence (AC-003 AC-004)' do
    it 'returns nil ratios when the store has no product at all' do
      metric = coverage.metric_for('missing_seo')

      expect(metric.total).to eq(0)
      expect(metric.missing_ratio).to be_nil
      expect(metric.coverage_ratio).to be_nil
      expect(metric).not_to be_computable
      expect(coverage).to be_empty
    end

    # "门店没有其它语言" ≠ "翻译完成 100%"
    it 'returns nil for translations when there is no other locale' do
      monolingual = create(:store, code: "ch_cov_mono_#{SecureRandom.hex(4)}",
                                   default_locale: 'en', supported_locales: 'en')
      create(:product, store: monolingual, status: 'active')

      metric = described_class.call(monolingual).metric_for('missing_translations')

      expect(metric.total).to eq(0)
      expect(metric.missing_ratio).to be_nil
      expect(metric).not_to be_computable
    end

    it 'never renders a percentage for an uncomputable metric' do
      expect(coverage.metric_for('missing_seo').missing_percentage).to be_nil
      expect(coverage.metric_for('missing_seo').coverage_percentage).to be_nil
    end
  end

  describe 'read-only (AC-007)' do
    before { create(:product, store: store, status: 'active') }

    it 'never writes anything' do
      expect { coverage.metrics }.not_to change {
        PallasTrade::CatalogHealthSnapshot.count +
          PallasTrade::Product.count +
          PallasTrade::AuditLog.count
      }
    end
  end

  describe 'shape' do
    it 'always exposes both metrics in a stable order' do
      expect(coverage.metrics.map(&:key)).to eq(%w[missing_seo missing_translations])
    end

    it 'keeps its query count flat as products grow' do
      create(:product, store: store, status: 'active')
      # 预热：首次调用会带上 schema / prepared statement 的一次性查询，不该算进增量比较
      described_class.call(store).metrics.map(&:missing)
      small = count_queries { described_class.call(store).metrics.map(&:missing) }

      10.times { create(:product, store: store, status: 'active') }
      large = count_queries { described_class.call(store).metrics.map(&:missing) }

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
