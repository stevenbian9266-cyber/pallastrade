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
end
