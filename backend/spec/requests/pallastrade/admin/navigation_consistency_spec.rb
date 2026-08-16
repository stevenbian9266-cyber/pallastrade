# frozen_string_literal: true

require 'rails_helper'

# PRD-20260816-admin-管理后台导航架构统一重构-常显原则-面包屑自动推导-单一布局 AC-006 AC-007 AC-008 AC-009 AC-010 AC-011
# 统一单一侧边栏：顶级落地 landing、tab 面包屑、全配置化 + 双语、常显回归。
# 历史 AC 覆盖：AC-001（头部溢出）AC-002（常显）AC-003（自动推导）AC-004（单一布局）AC-005（设置区 crumb）
RSpec.describe 'Admin navigation (P6 unified sidebar: landing + tabs + config)', type: :request do
  let(:store) { create(:store, code: 'nav_p6_test') }
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
      PallasTrade::Admin::GiftCardsController,
      PallasTrade::Admin::AdminUsersController,
      PallasTrade::Admin::WebhookEndpointsController,
      PallasTrade::Admin::TaxRatesController,
      PallasTrade::Admin::RolesController,
      PallasTrade::Admin::StorefrontController,
      PallasTrade::Admin::CustomerReturnsController,
      PallasTrade::Admin::StockItemsController,
      PallasTrade::Admin::StockMovementsController,
      PallasTrade::Admin::StockTransfersController,
      PallasTrade::Admin::ReportsController,
      PallasTrade::Admin::PoliciesController,
      PallasTrade::Admin::MarketsController,
      PallasTrade::Admin::PaymentMethodsController,
      PallasTrade::Admin::ShippingMethodsController,
      PallasTrade::Admin::TaxCategoriesController,
      PallasTrade::Admin::InvitationsController,
      PallasTrade::Admin::AllowedOriginsController,
      PallasTrade::Admin::RedirectsController,
      PallasTrade::Admin::ExportsController,
      PallasTrade::Admin::ImportsController,
      PallasTrade::Admin::ReturnAuthorizationReasonsController,
      PallasTrade::Admin::RefundReasonsController,
      PallasTrade::Admin::ReimbursementTypesController,
      PallasTrade::Admin::StockLocationsController,
      PallasTrade::Admin::MetafieldDefinitionsController,
      PallasTrade::Admin::CustomerGroupsController,
      PallasTrade::Admin::NewsletterSubscribersController,
      PallasTrade::Admin::OptionTypesController,
      PallasTrade::Admin::TaxonomiesController,
      PallasTrade::Admin::PriceListsController,
      PallasTrade::Admin::ReturnAuthorizationsController,
      PallasTrade::Admin::EmailLogsController,
      PallasTrade::Admin::ContactMessagesController,
      PallasTrade::Admin::EmailNotificationScenariosController
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

  def breadcrumb_text
    doc = Nokogiri::HTML(response.body)
    doc.at_css('nav[aria-label="breadcrumb"]')&.text.to_s
  end

  def sidebar
    @sidebar ||= PallasTrade.admin.navigation.sidebar
  end

  # ============================================================
  # AC-007：全配置化 — 统一单一树 + 子菜单完整 + landing = 第一个子项
  # ============================================================
  describe 'AC-007 — 统一单一树 + 子菜单 + landing 配置' do
    it '没有独立 settings/admin_users 顶级项（设置区已融入主区）' do
      keys = sidebar.root_items.map(&:key)
      expect(keys).not_to include(:settings)
      expect(keys).not_to include(:admin_users)
    end

    it '设置模块成为顶级可收拉项' do
      keys = sidebar.root_items.map(&:key)
      expect(keys).to include(:developers, :users, :tax, :shipping, :audits, :return_settings)
    end

    it '主区模块子菜单完整（Orders / Products / Customers / Promotions / Reports / Blog / Returns）' do
      expect(sidebar.find(:orders).children.map(&:key)).to eq(%i[all_orders orders_to_fulfill draft_orders])
      expect(sidebar.find(:products).children.map(&:key)).to eq(%i[products_list price_lists stock translations taxonomies options])
      expect(sidebar.find(:customers).children.map(&:key)).to eq(%i[customers_list customer_groups newsletter_subscribers])
      expect(sidebar.find(:promotions).children.map(&:key)).to eq(%i[promotions_list gift_cards])
      expect(sidebar.find(:reports).children.map(&:key)).to eq(%i[reports_list])
      expect(sidebar.find(:blog).children.map(&:key)).to eq(%i[blog_list])
      expect(sidebar.find(:returns).children.map(&:key)).to eq(%i[customer_returns return_authorizations])
    end

    it '设置模块子菜单完整（Developers / Users / Tax / Shipping / Audit / Return Settings）' do
      expect(sidebar.find(:developers).children.map(&:key)).to eq(%i[api_keys webhook_endpoints allowed_origins redirects])
      expect(sidebar.find(:users).children.map(&:key)).to eq(%i[admin_users invitations roles])
      expect(sidebar.find(:tax).children.map(&:key)).to eq(%i[tax_rates tax_categories])
      expect(sidebar.find(:shipping).children.map(&:key)).to eq(%i[shipping_methods shipping_categories])
      expect(sidebar.find(:audits).children.map(&:key)).to eq(%i[audit_log exports imports])
      expect(sidebar.find(:return_settings).children.map(&:key)).to eq(%i[return_authorization_reasons refund_reasons reimbursement_types])
    end

    it '每个有子项的顶级项都声明 landing 指向存在的子项，且 landing 是第一个子项' do
      sidebar.root_items.select { |item| item.children.any? }.each do |item|
        expect(item.landing).not_to be_nil, "#{item.key} 缺少 landing"
        landing = item.children.find { |c| c.key == item.landing }
        expect(landing).not_to be_nil, "#{item.key} landing 指向不存在的子项"
        expect(landing.position).to eq(item.children.map(&:position).min), "#{item.key} landing 不是第一个子项"
      end
    end

    it 'Stock 子项声明 tabs: :stock_tabs（页面级 tab 上下文）' do
      stock = sidebar.find(:products).children.find { |c| c.key == :stock }
      expect(stock.tabs).to eq(:stock_tabs)
      expect(PallasTrade.admin.navigation.context?(:stock_tabs)).to be(true)
    end
  end

  # ============================================================
  # AC-006：顶级落地 — 点击一级落到 landing 子项 + 面包屑 一级 > 二级
  # ============================================================
  describe 'AC-006 — 顶级落地 + 一级 > 二级面包屑' do
    it '顶级链接指向 landing（Orders → /admin/orders，Developers → /admin/api_keys）' do
      get '/admin/orders'
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('#nav-link-orders')['href']).to eq('/admin/orders')

      get '/admin/api_keys'
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('#nav-link-developers')['href']).to eq('/admin/api_keys')
    end

    it '面包屑 Orders > All Orders 于 /admin/orders' do
      get '/admin/orders'
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:orders))
      expect(crumb).to include(PallasTrade.t('admin.orders.all_orders'))
    end

    it '面包屑 Orders > Orders to Fulfill 于待发货筛选页（query 感知）' do
      item = sidebar.find(:orders).children.find { |c| c.key == :orders_to_fulfill }
      url = item.resolve_url
      get url
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:orders))
      expect(crumb).to include(PallasTrade.t('admin.orders.orders_to_fulfill'))
    end

    it '面包屑 Products > Products List 于 /admin/products' do
      get '/admin/products'
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:products))
      expect(crumb).to include(PallasTrade.t('admin.products.products_list'))
    end

    it '面包屑 Returns > Customer Returns 于 /admin/customer_returns' do
      get '/admin/customer_returns'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:returns))
      expect(crumb).to include(PallasTrade.t('admin.returns.customer_returns'))
    end
  end

  # ============================================================
  # AC-009：设置模块三段式面包屑（无 Settings 前缀）
  # ============================================================
  describe 'AC-009 — 设置模块面包屑无 Settings 前缀' do
    it 'Developers > API Keys 于 /admin/api_keys（无 Settings 前缀，无 Home 泄漏）' do
      get '/admin/api_keys'
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:developers))
      expect(crumb).to include(PallasTrade.t(:api_keys))
      expect(crumb).not_to include(PallasTrade.t(:settings))
      expect(crumb).not_to include(PallasTrade.t(:home))
    end

    it 'Developers > Webhook Endpoints 于 /admin/webhook_endpoints' do
      get '/admin/webhook_endpoints'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:developers))
      expect(crumb).to include(PallasTrade.t(:webhook_endpoints))
      expect(crumb).not_to include(PallasTrade.t(:settings))
    end

    it 'Users > Roles 于 /admin/roles' do
      get '/admin/roles'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:users))
      expect(crumb).to include(PallasTrade.t(:roles))
      expect(crumb).not_to include(PallasTrade.t(:settings))
    end

    it 'Tax > Tax Rates 于 /admin/tax_rates' do
      get '/admin/tax_rates'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:tax))
      expect(crumb).to include(PallasTrade.t(:tax_rates))
      expect(crumb).not_to include(PallasTrade.t(:settings))
    end

    it '叶子项单 crumb（Storefront）于 /admin/storefront' do
      get '/admin/storefront'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t('admin.storefront'))
      expect(crumb).not_to include(PallasTrade.t(:settings))
    end
  end

  # ============================================================
  # AC-008：Stock 三 tab 面包屑 + 页面头
  # ============================================================
  describe 'AC-008 — Stock tabs 面包屑 + 页面头' do
    it 'Products > Stock > Stock Items 于 /admin/stock_items' do
      get '/admin/stock_items'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:products))
      expect(crumb).to include(PallasTrade.t(:stock))
      expect(crumb).to include(PallasTrade.t(:stock_items))
      expect(response.body).to include('id="page-header"')
    end

    it 'Products > Stock > Stock Movements 于 /admin/stock_movements' do
      get '/admin/stock_movements'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:products))
      expect(crumb).to include(PallasTrade.t(:stock))
      expect(crumb).to include(PallasTrade.t(:stock_movements))
      expect(response.body).to include('id="page-header"')
    end

    it 'Products > Stock > Stock Transfers 于 /admin/stock_transfers' do
      get '/admin/stock_transfers'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:products))
      expect(crumb).to include(PallasTrade.t(:stock))
      expect(crumb).to include(PallasTrade.t(:stock_transfers))
      expect(response.body).to include('id="page-header"')
    end
  end

  # ============================================================
  # AC-010：深层面包屑完整路径 + 末级前可点击
  # ============================================================
  describe 'AC-010 — 深层面包屑' do
    it 'Products > Products List > 产品名 于 /admin/products/:id/edit' do
      product = create(:product, store: store, name: 'P6 Deep Crumb Product')
      get "/admin/products/#{product.slug}/edit"
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:products))
      expect(crumb).to include(PallasTrade.t('admin.products.products_list'))
      expect(crumb).to include('P6 Deep Crumb Product')
    end
  end

  # ============================================================
  # AC-011：i18n 双语（新增 label en + zh-CN 必填）
  # ============================================================
  describe 'AC-011 — 新增 label 双语（en/zh-CN）' do
    let(:bilingual_keys) do
      %w[
        admin.orders.all_orders
        admin.products.products_list
        admin.products.categories
        admin.customers.customers_list
        admin.promotions.promotions_list
        admin.reports.reports_list
        admin.blog.blog_list
        admin.returns.customer_returns
        admin.users.admin_users
        admin.ai.overview
      ]
    end

    it '每个新增 label 在 en 与 zh-CN 都存在' do
      %w[en zh-CN].each do |locale|
        bilingual_keys.each do |key|
          expect(I18n.with_locale(locale) { I18n.exists?("pallastrade.#{key}", locale) })
            .to be(true), "#{key} 缺少 #{locale} 翻译"
        end
      end
    end
  end

  # ============================================================
  # 回归：常显原则 + 单一布局 + 设置区 section/tabs 统一（P2/P4）
  # ============================================================
  describe '回归 — 常显原则（AC-002）' do
    # PRD-20260816-admin-管理后台导航架构统一重构-常显原则-面包屑自动推导-单一布局 AC-002
    it 'keeps Orders to Fulfill visible on /admin/orders even with zero ready-to-ship orders' do
      get '/admin/orders'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.orders.orders_to_fulfill'))
      expect(response.body).to include('nav-submenu-orders')
    end

    it 'keeps Translations visible on /admin/products for single-locale stores' do
      allow(store).to receive(:supported_locales_list).and_return(['en'])
      get '/admin/products'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t(:translations))
    end
  end

  describe '回归 — 单一布局 + 设置区 section/tabs 统一（AC-004）' do
    # PRD-20260816-admin-管理后台导航架构统一重构-常显原则-面包屑自动推导-单一布局 AC-004
    it 'renders /admin/api_keys with main layout + Developers section banner + page header' do
      get '/admin/api_keys'
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('admin-settings')
      expect(response.body).to include('id="page-header"')
      doc = Nokogiri::HTML(response.body)
      header_title = doc.at_css('#page-header #page_title')&.text.to_s
      # P4 单一布局：设置页页面头标题为 section banner 名（Developers）
      expect(header_title).to include(PallasTrade.t(:developers))
      tabs_text = doc.at_css('#page-tabs')&.text.to_s
      expect(tabs_text).to include(PallasTrade.t(:api_keys))
      expect(tabs_text).to include(PallasTrade.t(:webhook_endpoints))
    end

    it 'renders /admin/admin_users with Team section banner + invite action' do
      get '/admin/admin_users'
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('admin-settings')
      expect(response.body).to include('id="page-header"')
      doc = Nokogiri::HTML(response.body)
      header_title = doc.at_css('#page-header #page_title')&.text.to_s
      expect(header_title).to include(PallasTrade.t(:users))
      tabs_text = doc.at_css('#page-tabs')&.text.to_s
      expect(tabs_text).to include(PallasTrade.t(:invitations))
      expect(tabs_text).to include(PallasTrade.t(:roles))
    end
  end

  describe '回归 — 面包屑自动推导（AC-003）' do
    # PRD-20260816-admin-管理后台导航架构统一重构-常显原则-面包屑自动推导-单一布局 AC-003
    it 'derives Emails > Email Settings on /admin/emails' do
      get '/admin/emails'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:emails))
      expect(crumb).to include(PallasTrade.t('admin.emails.settings'))
    end

    it 'derives Orders > Draft Orders on /admin/checkouts' do
      get '/admin/checkouts'
      expect(response).to have_http_status(:ok)
      crumb = breadcrumb_text
      expect(crumb).to include(PallasTrade.t(:orders))
      expect(crumb).to include(PallasTrade.t(:draft_orders))
    end
  end
end
