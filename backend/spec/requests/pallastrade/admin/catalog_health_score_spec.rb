# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-health-score
#   AC-001 7 类 issue 都有覆盖率；内容三维分母 = 未归档商品数
#   AC-002 库存维分母 = 未归档且 active 的商品数；草稿维分母 = 未归档且 draft 的商品数
#   AC-003 翻译维分母 = 商品 × 其它语言槽位；URL 维分母 = 变更总条数
#   AC-004 分母为 0 → 该维不可计算，且**不计入**总分
#   AC-005 总分 == 按权重手工复算；全不可计算 → 总分为 nil
#   AC-006 页面同时渲染总分、每维分子/分母、计入与否与未计入原因
#   AC-007 每维分子 == Issues.count（逐 key）
#   AC-008 单维计数抛错 → 按不可计算处理，且**不会**出现该维满分的虚高
#   AC-009 计算与渲染零写入
RSpec.describe 'Admin catalog health score', type: :request do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let!(:store) do
    create(:store, code: "ch_score_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', supported_locales: 'en,de',
                   name: 'Score Store')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  # 三个状态各来一个：**分母必须真的不同**才能证明「没有共用一个分母」。
  # 全是 active 的店会让 active 计数恰好等于商品总数，测不出任何东西。
  let!(:active_product) { create(:product, store: store, status: 'active') }
  let!(:draft_product) { create(:product, store: store, status: 'draft') }
  let!(:archived_product) { create(:product, store: store, status: 'archived') }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def coverage
    PallasTrade::CatalogHealth::Coverage.call(store)
  end

  def score
    PallasTrade::CatalogHealth::Score.call(store)
  end

  before do
    PallasTrade::CatalogHealthSnapshot.delete_all
    sign_in_as_admin
  end

  describe 'coverage denominators (AC-001/AC-002/AC-003)' do
    # 与 Issues 的 scope 同源：已归档商品不进任何一类。
    let(:not_archived) { store.products.not_archived.count }
    let(:active_products) { store.products.not_archived.where(status: 'active').count }
    let(:draft_products) { store.products.not_archived.where(status: 'draft').count }

    it 'gives every issue key a metric (AC-001)' do
      expect(coverage.metrics.map(&:key)).to eq(PallasTrade::CatalogHealth::Issues::KEYS)
    end

    it 'uses the not-archived product count for the three content issues (AC-001)' do
      %w[missing_media missing_description missing_seo].each do |key|
        expect(coverage.metric_for(key).total).to eq(not_archived), "#{key} denominator"
      end
    end

    it 'narrows the stock and draft denominators to their own subset (AC-002)' do
      # 前提：这个店的 active / draft 计数与商品总数**不相等**，否则断言毫无意义。
      expect(active_products).not_to eq(not_archived)
      expect(draft_products).not_to eq(not_archived)

      expect(coverage.metric_for('active_zero_stock').total).to eq(active_products)
      expect(coverage.metric_for('active_zero_stock').total).not_to eq(not_archived)
      expect(coverage.metric_for('old_drafts').total).to eq(draft_products)
      expect(coverage.metric_for('old_drafts').total).not_to eq(not_archived)
    end

    it 'uses the (product x locale) slots for translations (AC-003)' do
      metric = coverage.metric_for('missing_translations')

      # 与**分子**同源才是重点：`Issues.translation_slots` 用的是 `store.product_ids`，
      # 也就是**含已归档**的全量商品，而内容三类走的是 `not_archived`。
      # 两套集合不同是既有 `Issues` 的口径（本 PRD 不改动它），但不影响这个比率是对的 ——
      # 只要分子与分母用同一套集合就行，否则算出来才是错的。
      expect(metric.total).to eq(PallasTrade::CatalogHealth::Issues.translation_slots(store))
      # supported_locales: en,de → 1 个「其它语言」，故槽位 = 全量商品数 × 1。
      expect(metric.total).to eq(store.product_ids.size)
      expect(metric.total).not_to eq(not_archived)
    end

    it 'uses the URL-change count for unresolved redirects (AC-003)' do
      expect(coverage.metric_for('redirect_unresolved').total)
        .to eq(PallasTrade::ProductUrlChange.call(store).count)
    end
  end

  describe 'exclusion (AC-004)' do
    it 'leaves a dimension without a denominator out of the score' do
      # 这个店没有任何 URL 变更 → URL 维无分母；它不能按 0 或 1 参与。
      dimension = score.dimensions.find { |d| d.key == 'redirect_unresolved' }

      expect(dimension.total).to be_zero
      expect(dimension.counted).to be(false)
      expect(dimension.excluded_reason).to eq(:no_denominator)
      expect(score.counted_count).to be < score.dimension_count
    end

    it 'counts a dimension that does have a denominator' do
      dimension = score.dimensions.find { |d| d.key == 'missing_seo' }

      expect(dimension.counted).to be(true)
      expect(dimension.excluded_reason).to be_nil
    end
  end

  describe 'score arithmetic (AC-005)' do
    it 'can be recomputed by hand from the dimensions on the page' do
      counted = score.dimensions.select(&:counted)
      manual = counted.sum { |d| d.weight * d.coverage_ratio } / counted.sum(&:weight)

      expect((manual * 100).round).to eq(score.out_of_100)
    end

    it 'weighs every dimension equally so the number stays explainable' do
      weights = score.dimensions.map(&:weight).uniq

      expect(weights).to eq([1.0])
    end

    it 'reports no score at all when nothing is measurable' do
      # 只把商品改成 archived 是不够的：翻译维的分母走的是 `store.product_ids`
      # （含已归档），仍然可计算 —— 要让什么都量不了，店里得真的没有商品。
      store.products.destroy_all

      expect(score.computable?).to be(false)
      expect(score.out_of_100).to be_nil
      expect(score.counted_count).to be_zero
    end
  end

  describe 'molecule discipline (AC-007)' do
    it 'takes every molecule from Issues.count' do
      PallasTrade::CatalogHealth::Issues::KEYS.each do |key|
        expect(coverage.metric_for(key).missing)
          .to eq(PallasTrade::CatalogHealth::Issues.count(store, key)), "molecule for #{key}"
      end
    end
  end

  describe 'a broken counter (AC-008)' do
    before do
      allow(PallasTrade::CatalogHealth::Issues).to receive(:count).and_call_original
      allow(PallasTrade::CatalogHealth::Issues).to receive(:count)
        .with(store, 'missing_media').and_raise('counter exploded')
    end

    it 'excludes the failed dimension instead of reading its zero as a perfect score' do
      dimension = score.dimensions.find { |d| d.key == 'missing_media' }

      expect(dimension.counted).to be(false)
      expect(dimension.excluded_reason).to eq(:count_failed)

      # 关键：它**不能**以 100% 参与 —— 那会把总分凭空抬高。
      counted = score.dimensions.select(&:counted)
      expect(counted.map(&:key)).not_to include('missing_media')

      manual = counted.sum { |d| d.weight * d.coverage_ratio } / counted.sum(&:weight)
      expect((manual * 100).round).to eq(score.out_of_100)
    end
  end

  describe 'rendering (AC-006)' do
    it 'shows the score, its weighting and every dimension row' do
      get '/admin/catalog_health'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.score.heading'))
      expect(response.body).to include(score.out_of_100.to_s)
      expect(response.body).to include(
        PallasTrade.t('admin.catalog_health.score.weighting',
                      counted: score.counted_count, total: score.dimension_count)
      )

      score.dimensions.each do |dimension|
        expect(response.body).to include(PallasTrade.t("admin.catalog_health.issues.#{dimension.key}"))
      end
    end

    it 'says why a dimension was left out rather than leaving the merchant to guess' do
      get '/admin/catalog_health'

      expect(response.body).to include(
        PallasTrade.t('admin.catalog_health.score.excluded.no_denominator')
      )
    end

    it 'renders the molecules and denominators so the number can be re-checked' do
      get '/admin/catalog_health'

      dimension = score.dimensions.find { |d| d.key == 'missing_seo' }
      expect(response.body).to include("#{dimension.coverage_percentage}%")
      expect(response.body).to include(
        PallasTrade.t('admin.catalog_health.coverage.missing_of_total',
                      missing: dimension.missing, total: dimension.total)
      )
    end

    it 'shows an honest empty state instead of a number when no dimension is measurable' do
      store.products.destroy_all

      get '/admin/catalog_health'

      expect(response.body).to include(PallasTrade.t('admin.catalog_health.score.unknown'))
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.score.unknown_hint'))
    end

    it 'renders in Chinese for a Chinese admin locale' do
      store.update!(preferred_admin_locale: 'zh-CN')

      get '/admin/catalog_health'

      expect(response.body).to include('健康分')
      expect(response.body).to include('未计入 —— 本店暂无可衡量的对象')
      expect(response.body).not_to include('translation missing')
    end
  end

  describe 'read-only (AC-009)' do
    it 'writes nothing while computing and rendering' do
      expect do
        PallasTrade::CatalogHealth::Score.call(store)
        get '/admin/catalog_health'
      end.not_to change { PallasTrade::CatalogHealthSnapshot.count }

      expect(store.products.reload.count).to eq(3)
    end
  end
end
