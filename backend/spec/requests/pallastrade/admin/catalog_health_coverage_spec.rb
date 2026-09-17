# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-health-coverage-ratios
#   AC-006 工作台渲染两个比率（含分子/分母），分母为 0 时显示空态文案
#   AC-009 中文后台渲染无 translation missing（含新增 coverage 文案）
RSpec.describe 'Admin catalog health coverage ratios', type: :request do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let!(:store) do
    create(:store, code: "ch_cov_req_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', supported_locales: 'en,de',
                   name: 'Coverage Store')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  before do
    PallasTrade::CatalogHealthSnapshot.delete_all
    sign_in_as_admin
  end

  describe 'rendering (AC-006)' do
    it 'shows the coverage block with both metrics' do
      get '/admin/catalog_health'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.coverage.heading'))
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.coverage.metrics.missing_seo'))
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.coverage.metrics.missing_translations'))
    end

    it 'renders a percentage plus the molecule and denominator so it can be re-checked by hand' do
      create(:product, store: store, status: 'active')

      get '/admin/catalog_health'

      metric = PallasTrade::CatalogHealth::Coverage.call(store).metric_for('missing_seo')
      expect(metric).to be_computable
      expect(response.body).to include("#{metric.coverage_percentage}%")
      expect(response.body).to include(
        PallasTrade.t('admin.catalog_health.coverage.missing_of_total',
                      missing: metric.missing, total: metric.total)
      )
    end

    # 新店：0% 会让人以为"已做完"，100% 会让人以为"全坏了" —— 两者都是编造。
    it 'shows the honest empty state instead of a percentage when nothing is measurable' do
      get '/admin/catalog_health'

      expect(response.body).to include(PallasTrade.t('admin.catalog_health.coverage.unknown'))
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.coverage.unknown_hint'))
    end

    it 'keeps the seven issue counts and their links' do
      get '/admin/catalog_health'

      PallasTrade::CatalogHealth::Issues::KEYS.each do |key|
        expect(response.body).to include(PallasTrade.t("admin.catalog_health.issues.#{key}"))
      end
    end
  end

  describe 'Chinese admin locale (AC-009)' do
    before { store.update!(preferred_admin_locale: 'zh-CN') }

    it 'renders the coverage block in Chinese' do
      create(:product, store: store, status: 'active')

      get '/admin/catalog_health'

      expect(response.body).to include('覆盖率')
      expect(response.body).to include('SEO 覆盖率')
      expect(response.body).to include('翻译覆盖率')
    end

    it 'never leaks a translation-missing string anywhere on the page' do
      get '/admin/catalog_health'

      expect(response.body.scan(/translation missing: [^<"&]+/i)).to be_empty
    end

    it 'shows the Chinese empty state' do
      get '/admin/catalog_health'

      expect(response.body).to include('暂无数据')
    end
  end
end
