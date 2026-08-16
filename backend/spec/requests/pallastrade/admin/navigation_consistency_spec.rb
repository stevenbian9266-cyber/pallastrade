# frozen_string_literal: true

require 'rails_helper'

# PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一 AC-001 / AC-002 / AC-003 / AC-004 / AC-006
# 主区（Email 模式）与设置区（Settings 模式）的面包屑 + 页面头一致性回归。
RSpec.describe 'Admin navigation consistency (breadcrumb + page_title)', type: :request do
  let(:store) { create(:store, code: 'nav_consistency_test') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  # 所有被访问的控制器都 stub current_store，避免依赖会话 store
  def stub_current_store!
    [
      PallasTrade::Admin::PostsController,
      PallasTrade::Admin::ChannelsController,
      PallasTrade::Admin::ApiKeysController,
      PallasTrade::Admin::ZonesController,
      PallasTrade::Admin::BackInStockSubscriptionsController,
      PallasTrade::Admin::EmailTemplatesController,
      PallasTrade::Admin::StoresController
    ].each do |klass|
      allow_any_instance_of(klass).to receive(:current_store).and_return(store)
    end
  end

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    stub_current_store!
  end

  describe '主区 — Blog（Email 模式）' do
    # PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一 AC-001 AC-002
    it 'renders breadcrumb Blog + page header + New Post action on /admin/posts' do
      get '/admin/posts'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('aria-label="breadcrumb"')
      expect(response.body).to include('id="page-header"')
      expect(response.body).to include(PallasTrade.t(:blog))
      expect(response.body).to include(PallasTrade.t('admin.posts.new_post'))
    end
  end

  describe '设置区 — Settings 模式（自动 Settings 前缀 + 页面 crumb + 页面头）' do
    # PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一 AC-006
    it 'keeps existing email pages consistent (regression coverage alongside emails_spec)' do
      get '/admin/email_templates'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('aria-label="breadcrumb"')
    end

    # PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一 AC-003
    it 'renders Settings > Sales channels breadcrumb + page header on /admin/channels' do
      get '/admin/channels'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('aria-label="breadcrumb"')
      expect(response.body).to include(PallasTrade.t(:settings))
      expect(response.body).to include(PallasTrade.t(:channels))
      expect(response.body).to include('id="page-header"')
    end

    # PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一 AC-003
    it 'renders Settings > API Keys breadcrumb on /admin/api_keys' do
      get '/admin/api_keys'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t(:settings))
      expect(response.body).to include(PallasTrade.t(:api_keys))
    end

    # PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一 AC-003
    it 'renders Settings > Zones breadcrumb + page header on /admin/zones' do
      get '/admin/zones'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t(:settings))
      expect(response.body).to include(PallasTrade.t(:zones))
      expect(response.body).to include('id="page-header"')
    end

    # PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一 AC-004
    it 'renders page header on /admin/back_in_stock_subscriptions (was missing page_title)' do
      get '/admin/back_in_stock_subscriptions'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="page-header"')
      expect(response.body).to include(PallasTrade.t(:back_in_stock_subscriptions))
    end
  end
end
