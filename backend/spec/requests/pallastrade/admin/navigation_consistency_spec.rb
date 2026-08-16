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
      PallasTrade::Admin::OrdersController,
      PallasTrade::Admin::ProductsController,
      PallasTrade::Admin::ProductTranslationsController,
      PallasTrade::Admin::StoresController,
      PallasTrade::Admin::EmailsController,
      PallasTrade::Admin::CheckoutsController,
      PallasTrade::Admin::GiftCardsController
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

  describe '架构重构 — 常显原则（PRD-20260816-admin-管理后台导航架构统一重构）' do
    # PRD-20260816-admin-管理后台导航架构统一重构 AC-002
    it 'keeps Orders to Fulfill visible on /admin/orders even with zero ready-to-ship orders' do
      # 测试商店无待发货订单 → ready_to_ship_orders_count 为 0/nil，菜单仍应常显
      get '/admin/orders'
      expect(response).to have_http_status(:ok)
      # 常显原则：次级菜单不再因业务状态（count>0）隐藏
      expect(response.body).to include(PallasTrade.t('admin.orders.orders_to_fulfill'))
      expect(response.body).to include('nav-submenu-orders')
    end

    # PRD-20260816-admin-管理后台导航架构统一重构 AC-002
    it 'keeps Translations visible on /admin/products for single-locale stores' do
      allow(store).to receive(:supported_locales_list).and_return(['en'])
      get '/admin/products'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t(:translations))
    end

    # PRD-20260816-admin-管理后台导航架构统一重构 AC-002
    it 'renders translations empty-state guidance for single-locale stores' do
      allow(store).to receive(:supported_locales_list).and_return(['en'])
      get '/admin/product_translations'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.product_translations.no_locales_title'))
    end
  end

  describe '架构重构 — 面包屑自动推导（PRD-20260816-admin-管理后台导航架构统一重构 AC-003）' do
    # 主区模块页面包屑由导航配置自动推导，不再依赖手写 concern/crumb
    it 'derives Emails > Email Settings on /admin/emails' do
      get '/admin/emails'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t(:emails))
      expect(response.body).to include(PallasTrade.t('admin.emails.settings'))
    end

    it 'derives Orders > Draft Orders on /admin/checkouts' do
      get '/admin/checkouts'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t(:orders))
      expect(response.body).to include(PallasTrade.t(:draft_orders))
    end

    it 'derives Promotions > Gift Cards on /admin/gift_cards' do
      get '/admin/gift_cards'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t(:promotions))
      expect(response.body).to include(PallasTrade.t(:gift_cards))
    end

    it 'derives Products > Translations on /admin/product_translations' do
      get '/admin/product_translations'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t(:products))
      expect(response.body).to include(PallasTrade.t(:translations))
    end

    it 'derives Products + product name on /admin/products/:id/edit (object crumb)' do
      product = create(:product, store: store, name: 'Auto Crumb Test Product')
      get "/admin/products/#{product.slug}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t(:products))
      expect(response.body).to include('Auto Crumb Test Product')
    end
  end
end
