# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-operations-report AC-007 AC-008（商品域审计 G-6）
#   AC-007 只读页面渲染（三段 + 窗口切换 + 空态 + 全库口径声明）
#   AC-008 权限（Product read）+ 未登录重定向
RSpec.describe 'Admin catalog operations report', type: :request do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let!(:store) do
    create(:store, code: "catalog_ops_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', name: 'Ops Store')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:product) { create(:product, store: store) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  # 报表读的是全库审计表，用例内先清空，断言只面对本用例写入的条目（事务内，回滚安全）
  before { PallasTrade::AuditLog.delete_all }

  def entry(action:, at: Time.current, actor: 'alice@example.com', metadata: {})
    PallasTrade::AuditLog.create!(
      resource_type: 'PallasTrade::Product',
      resource_id: product.id,
      action: action,
      actor_label: actor,
      metadata: metadata.presence,
      occurred_at: at
    )
  end

  describe 'read-only roll-up rendering (AC-007)' do
    before { sign_in_as_admin }

    it 'renders both operation kinds and the maintenance block' do
      entry(action: 'product.bulk_price_updated', metadata: { 'source' => 'bulk' })
      entry(action: 'product.updated', metadata: { 'changed' => ['name'] })

      get '/admin/catalog_operations'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.catalog_operations.title'))
      expect(response.body).to include(PallasTrade.t('admin.catalog_operations.kinds.bulk'))
      expect(response.body).to include(PallasTrade.t('admin.catalog_operations.kinds.single'))
      expect(response.body).to include(PallasTrade.t('admin.catalog_operations.maintenance_heading'))
    end

    it 'shows the empty state when nothing moved in the window' do
      get '/admin/catalog_operations'

      expect(response.body).to include(PallasTrade.t('admin.catalog_operations.empty'))
    end

    it 'switches to the 30-day window and falls back for unknown values' do
      entry(action: 'product.updated', at: 10.days.ago)

      get '/admin/catalog_operations', params: { window: 30 }
      expect(response.body).to include(PallasTrade.t('admin.catalog_operations.window_days', count: 30))

      get '/admin/catalog_operations', params: { window: 999 }
      expect(response.body).to include(PallasTrade.t('admin.catalog_operations.window_days', count: 7))
    end

    it 'declares the all-stores scope instead of pretending to be store-scoped' do
      get '/admin/catalog_operations'

      expect(response.body).to include(PallasTrade.t('admin.catalog_operations.scope_note'))
    end

    it 'ranks actors, bucketing anonymous writes under system' do
      entry(action: 'product.updated', actor: nil)

      get '/admin/catalog_operations'

      expect(response.body).to include(PallasTrade::Catalog::Operations::Report::SYSTEM_ACTOR)
    end
  end

  describe 'authorization (AC-008)' do
    it 'redirects anonymous visitors' do
      get '/admin/catalog_operations'

      expect(response).to have_http_status(:redirect)
    end

    it 'serves the page to an admin holding product read permission' do
      sign_in_as_admin

      get '/admin/catalog_operations'

      expect(response).to have_http_status(:ok)
    end
  end
end
