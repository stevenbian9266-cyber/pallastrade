# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-admin-管理后台导航settings收起展开与新增fund一级菜单
#   AC-001 Settings 分区标题渲染为收起/展开开关（含折叠作用域锚点）
#   AC-003 Fund 一级菜单（landing + 子菜单 + 资金生命周期顺序）
#   AC-005 双语（en + zh-CN）
#   AC-006 菜单配置页与导航配置同源
#   AC-007 菜单权限子集下 Fund 顶级项可见且仅渲染被授权子项
RSpec.describe 'Admin navigation — collapsible Settings section + Fund menu', type: :request do
  let(:store) { create(:store, code: 'nav_fund_test') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  # 所有被访问的控制器都 stub current_store，避免依赖会话 store
  FUND_KEYS = %i[
    transactions payments_ops payment_combinations refunds refund_approvals
    disputes_ops dispute_rates reconciliation_cases payouts currency_rates
    fx_snapshots payment_costs payment_fee_policies risk_lists risk_rules payment_risk
  ].freeze

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)

    [PallasTrade::Admin::OrdersController, PallasTrade::Admin::MenuConfigsController].each do |klass|
      allow_any_instance_of(klass).to receive(:current_store).and_return(store)
    end
  end

  def doc
    @doc ||= Nokogiri::HTML(response.body)
  end

  def sidebar
    @sidebar ||= PallasTrade.admin.navigation.sidebar
  end

  def root_link_ids
    doc.css('#main-sidebar .sidebar-content > ul.nav > li > a.nav-link').map { |a| a['id'] }
  end

  describe 'AC-001 — Settings 分区标题渲染为收起 / 展开开关' do
    before { get '/admin/orders' }

    it '渲染 button（aria-expanded + click->sidebar#toggleSection + 语义 token + chevron）' do
      expect(response).to have_http_status(:ok)

      toggle = doc.at_css('#main-sidebar [data-nav-section-toggle="settings_section"]')
      expect(toggle).to be_present, '缺少 data-nav-section-toggle="settings_section"（折叠作用域锚点）'

      button = toggle.at_css('button[aria-expanded]')
      expect(button).to be_present, '分区标题未渲染为 button[aria-expanded]'
      expect(button['data-action']).to eq('click->sidebar#toggleSection')
      expect(button['aria-expanded']).to eq('true')
      expect(button['class']).to include('nav-section-toggle-btn')
      # 颜色契约：走语义 token，不直引调色板
      expect(button['class']).to include('text-text-subtle')
      expect(button['class']).not_to match(/text-(gray|zinc|slate|blue|neutral)-\d/)
      expect(button.at_css('i.nav-section-chevron')).to be_present
      expect(button['title']).to eq(PallasTrade.t('admin.nav_section_toggle_hint'))
    end

    it '折叠作用域 = 标题之后的同级元素（含带子菜单项的 submenu 兄弟节点）' do
      # 注：桌面侧边栏与移动侧边栏渲染同一棵导航树，选择器需限定 #main-sidebar
      toggle = doc.at_css('#main-sidebar [data-nav-section-toggle="settings_section"]')
      following = toggle.xpath('./following-sibling::*')

      # 带子菜单项会额外产生 <ul class="nav-submenu"> / <ul class="nav-submenu-dropdown">，
      # 它们是同一 <ul> 里的**兄弟节点**（不在 <li> 内）⇒ 折叠必须按「同级元素」整体处理。
      expect(following.map(&:name)).to include('li', 'ul')
      expect(following.map { |node| node['id'].to_s }).to include('nav-submenu-users')

      # 分区内条目在锚点之后；主区条目（Orders / Fund）在锚点之前 ⇒ 不影响主区菜单
      expect(toggle.xpath('./following-sibling::li//a[@id="nav-link-general_settings"]')).to be_present
      expect(toggle.xpath('./following-sibling::li//a[@id="nav-link-users"]')).to be_present
      expect(toggle.xpath('./preceding-sibling::li//a[@id="nav-link-orders"]')).to be_present
      expect(toggle.xpath('./preceding-sibling::li//a[@id="nav-link-fund"]')).to be_present
    end

    it '仅 Settings 分区可折叠（其它 section 标题保持纯文本，无回归）' do
      sections = sidebar.root_items.select(&:section?)
      expect(sections.map(&:key)).to eq([:settings_section])
      expect(sections.map(&:collapsible?).uniq).to eq([true])
    end
  end

  describe 'AC-003 — Fund 一级菜单' do
    before { get '/admin/orders' }

    it '位置紧跟 Orders（Orders → Fund → Returns）' do
      ids = root_link_ids
      expect(ids).to include('nav-link-orders', 'nav-link-fund', 'nav-link-returns')
      expect(ids.index('nav-link-orders')).to be < ids.index('nav-link-fund')
      expect(ids.index('nav-link-fund')).to be < ids.index('nav-link-returns')
    end

    it '顶级链接落到 landing（资金生命周期第一站 = 交易）' do
      expect(doc.at_css('#main-sidebar #nav-link-fund')['href']).to eq('/admin/transactions')
    end

    it '子菜单完整且顺序 = 资金生命周期序' do
      expect(doc.at_css('#main-sidebar #nav-submenu-fund')).to be_present
      child_ids = doc.css('#main-sidebar #nav-submenu-fund a.nav-link')
                     .map { |a| a['id'].to_s.sub('nav-link-', '') }
      expect(child_ids).to eq(FUND_KEYS.map(&:to_s))
    end

    it '导航模型与渲染同源（结构断言）' do
      expect(sidebar.find(:fund).children.map(&:key)).to eq(FUND_KEYS)
      expect(sidebar.find(:orders).children.map(&:key)).to eq(%i[all_orders orders_to_fulfill draft_orders])
      expect(sidebar.find(:fund).landing).to eq(:transactions)
    end
  end

  describe 'AC-005 — 双语（en + zh-CN）' do
    it 'Fund 标题与折叠提示键在两种语言下都存在' do
      %w[en zh-CN].each do |locale|
        %w[admin.fund.title admin.nav_section_toggle_hint].each do |key|
          expect(I18n.with_locale(locale) { I18n.exists?("pallastrade.#{key}", locale) })
            .to be(true), "#{key} 缺少 #{locale} 翻译"
        end
      end
    end

    it '渲染页面无 translation missing（中文门店不会静默缺译文）' do
      get '/admin/orders'
      expect(response.body.scan(/translation missing: [^<"&]+/i)).to be_empty
    end
  end

  describe 'AC-006 — 菜单配置页与导航配置同源' do
    it '展示 Fund 及其子项' do
      get '/admin/menu_configs'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.fund.title'))
      expect(response.body).to include(PallasTrade.t('admin.payouts.title'))
      expect(response.body).to include(PallasTrade.t('admin.risk_rules.title'))
    end
  end

  describe 'AC-007 — 菜单权限子集' do
    it '仅授权 Fund 子集时：Fund 顶级项可见且只渲染被授权子项' do
      allow_any_instance_of(PallasTrade::Ability)
        .to receive(:menu_permissions).and_return(%w[fund payouts])

      get '/admin/orders'
      expect(response).to have_http_status(:ok)

      expect(doc.at_css('#main-sidebar #nav-link-fund')).to be_present
      child_ids = doc.css('#main-sidebar #nav-submenu-fund a.nav-link')
                     .map { |a| a['id'].to_s.sub('nav-link-', '') }
      expect(child_ids).to eq(%w[payouts])
      # 未授权的主区菜单（Orders）不渲染
      expect(doc.at_css('#main-sidebar #nav-link-orders')).to be_nil
    end
  end
end
