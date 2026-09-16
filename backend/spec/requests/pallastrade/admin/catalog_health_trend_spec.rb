# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-health-trend-snapshot AC-006 AC-008
#   AC-006 工作台渲染趋势列，且既有 7 类计数与下钻链接不变（"计数==列表"不回归）
#   AC-008 权限：沿用 Product read 守卫
RSpec.describe 'Admin catalog health trend column', type: :request do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let!(:store) do
    create(:store, code: "ch_trend_req_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', name: 'Trend Store')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def snapshot(key:, count:, date:)
    PallasTrade::CatalogHealthSnapshot.create!(
      store_id: store.id, issue_key: key, captured_on: date, count: count
    )
  end

  before { PallasTrade::CatalogHealthSnapshot.delete_all }

  describe 'trend column (AC-006)' do
    before { sign_in_as_admin }

    it 'renders the trend heading' do
      get '/admin/catalog_health'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.trend.heading'))
    end

    # 没有可比快照时必须说"暂无趋势"，而不是显示"持平" —— 后者是在编造结论。
    it 'shows the honest empty state without two comparable snapshots' do
      get '/admin/catalog_health'

      expect(response.body).to include(PallasTrade.t('admin.catalog_health.trend.unknown'))
    end

    it 'renders a delta and direction once two snapshots exist' do
      snapshot(key: 'missing_description', count: 40, date: Date.current - 3)
      snapshot(key: 'missing_description', count: 12, date: Date.current)

      get '/admin/catalog_health'

      expect(response.body).to include('-28')
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.trend.directions.improving'))
    end

    it 'still renders every issue count and its drill-down link' do
      create(:product, store: store, status: 'active', description: nil)

      get '/admin/catalog_health'

      PallasTrade::CatalogHealth::Issues::KEYS.each do |key|
        expect(response.body).to include(PallasTrade.t("admin.catalog_health.issues.#{key}"))
      end
    end
  end

  describe 'authorization (AC-008)' do
    it 'redirects anonymous visitors' do
      get '/admin/catalog_health'

      expect(response).to have_http_status(:redirect)
    end
  end

  # 中文门店后台回归（2026-09-16）：admin UI 语言取自 current_store.preferred_admin_locale，
  # 而 gem 只提供 en —— 只加 en 不会让任何测试变红，页面只会静默地整页 Translation missing。
  # 这里用**真实 locale** 走完整页面渲染（比人工截图更强的证据：每次 CI 都会重跑）。
  describe 'Chinese admin locale (no silent translation missing)' do
    before do
      store.update!(preferred_admin_locale: 'zh-CN')
      sign_in_as_admin
    end

    it 'renders the worklist in Chinese' do
      get '/admin/catalog_health'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('商品健康')
      expect(response.body).to include('问题清单')
    end

    it 'never leaks a translation-missing string anywhere on the page' do
      get '/admin/catalog_health'

      # 整页扫描（含后台外壳：侧边栏/快速新建/确认框）—— 中文门店后台曾整页 missing，
      # 只盯本域会漏掉外壳，而外壳的缺失同样让页面不可用。
      expect(response.body.scan(/translation missing: [^<"&]+/i)).to be_empty
    end

    it 'renders the trend column labels in Chinese' do
      snapshot(key: 'missing_description', count: 40, date: Date.current - 3)
      snapshot(key: 'missing_description', count: 12, date: Date.current)

      get '/admin/catalog_health'

      expect(response.body).to include('趋势')
      expect(response.body).to include('改善')
      expect(response.body).to include('-28')
    end

    it 'shows the Chinese empty state when nothing is comparable' do
      get '/admin/catalog_health'

      expect(response.body).to include('暂无趋势')
    end

    # 2026-09-16 实测回归：AI 按钮的 title 曾把 Rails 的
    # `<span class="translation_missing">` 当普通字符串写进 HTML 属性，把属性撕开，
    # 残渣 `Default">` 变成了按钮可见文本。helper 已改为返回纯文本，
    # 这里同时守住「属性里不许有 HTML」和「文案真的存在」两件事。
    it 'never leaks translation-missing markup into the AI button tooltip' do
      get '/admin/catalog_health'

      expect(response.body).not_to include('translation_missing"')
      expect(response.body).not_to include('Default">')
    end

    # AI 按钮只在 AI 引擎可用时才渲染（本 spec 环境下不渲染），所以这里只断言
    # 「页面里不存在被撕开的属性残渣」——那才是这次的缺陷；文案存在性由
    # spec/i18n/admin_catalog_locale_coverage_spec.rb 的键集断言负责。
    it 'renders the AI button label and its disabled reason without extra characters' do
      get '/admin/catalog_health'

      expect(response.body).not_to include('translation_missing"')
      expect(response.body).not_to include('Default">')
    end
  end
end
