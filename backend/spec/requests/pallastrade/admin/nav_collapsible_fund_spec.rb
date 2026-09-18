# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-admin-管理后台导航settings收起展开与新增fund一级菜单
#   AC-001 Settings 分区标题渲染为收起/展开开关（含折叠作用域锚点）
#   AC-003 Fund 一级菜单（landing + 子菜单 + 资金生命周期顺序）
#   AC-005 双语（en + zh-CN）
#   AC-006 菜单配置页与导航配置同源
#   AC-007 菜单权限子集下 Fund 顶级项可见且仅渲染被授权子项
#   AC-010 v1.1：默认收起 / 展开仅二级 / hover 浮层容器（.dropdown-container）永不显形
#   AC-011 v1.1：点击二级 = 导航到落地页 + 展开其三级（首个三级为当前项）；主区菜单不受影响
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

    [PallasTrade::Admin::OrdersController, PallasTrade::Admin::MenuConfigsController,
     PallasTrade::Admin::PoliciesController, PallasTrade::Admin::AdminUsersController].each do |klass|
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

    it '渲染 button（aria-expanded=false 默认收起 + click->sidebar#toggleSection + 语义 token + chevron）' do
      expect(response).to have_http_status(:ok)

      toggle = doc.at_css('#main-sidebar [data-nav-section-toggle="settings_section"]')
      expect(toggle).to be_present, '缺少 data-nav-section-toggle="settings_section"（折叠作用域锚点）'

      button = toggle.at_css('button[aria-expanded]')
      expect(button).to be_present, '分区标题未渲染为 button[aria-expanded]'
      expect(button['data-action']).to eq('click->sidebar#toggleSection')
      # v1.1：默认收起（首次进入后台不显示分区内条目）
      expect(button['aria-expanded']).to eq('false')
      expect(toggle['data-nav-section-collapsed']).to eq('true')
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

  # ============================================================
  # AC-010/AC-011（v1.1 行为修正，用户实测反馈）
  #   默认收起 / 展开仅二级 / hover 浮层永不显形 / 点击二级展开三级
  # ============================================================
  describe 'AC-010 — 默认收起、展开仅二级、浮层容器永不显形' do
    it '/admin/orders（当前页不在分区内）→ 分区内二级条目服务端即 hidden' do
      get '/admin/orders'
      expect(response).to have_http_status(:ok)

      toggle = doc.at_css('#main-sidebar [data-nav-section-toggle="settings_section"]')

      # 分区条目范围以导航模型为准（settings_section 标题之后的顶级项，直到下一个分区标题）
      section_keys = sidebar.root_items.drop_while { |i| i.key != :settings_section }
                           .drop(1).take_while { |i| !i.section? }.map(&:key)
      expect(section_keys.size).to be >= 5, 'Settings 分区应包含多个二级条目'

      rendered = section_keys.filter_map do |key|
        li = doc.at_xpath("//*[@id='main-sidebar']//a[@id='nav-link-#{key}']/ancestor::li[1]")
        [key, li] if li
      end
      expect(rendered.size).to be >= 5, '分区内二级条目未被渲染'
      expect(rendered.map { |_key, li| li['class'].to_s.split.include?('hidden') }.uniq).to eq([true]),
             '默认收起：分区内二级条目必须全部带 hidden（首屏不得先展开后收起）'

      # 二级三级菜单与 hover 浮层容器也都保持 hidden
      toggle.xpath('./following-sibling::ul').each do |ul|
        expect(ul['class'].to_s.split).to include('hidden'), "#{ul['id']} 在收起态应为 hidden"
      end

      # 分区内不渲染任何箭头 icon（只有分区标题有 chevron）
      expect(toggle.xpath('./following-sibling::li//i[contains(@class, "chevron")]')).to be_empty
    end

    it '/admin/policies（当前页在分区内）→ 自动展开，且展开后只显示二级' do
      get '/admin/policies'
      expect(response).to have_http_status(:ok)

      toggle = doc.at_css('#main-sidebar [data-nav-section-toggle="settings_section"]')
      expect(toggle['data-nav-section-collapsed']).to eq('false'), '当前页在分区内 → 分区自动展开'
      expect(toggle.at_css('button[aria-expanded]')['aria-expanded']).to eq('true')

      # 二级条目可见
      expect(toggle.xpath('./following-sibling::li[not(contains(@class, "hidden"))]')).not_to be_empty

      # 非激活父项的三级仍收起（展开分区不等于展开三级）：作用域内所有 ul（三级 + hover 浮层）均 hidden
      scoped_uls = toggle.xpath('./following-sibling::ul')
      expect(scoped_uls).not_to be_empty
      scoped_uls.each do |ul|
        expect(ul['class'].to_s.split).to include('hidden'), "#{ul['id']} 不应随分区展开（三级保持收起）"
      end
    end

    it 'hover 下拉容器（.dropdown-container）无论收起还是展开都不得显形' do
      get '/admin/policies'

      dropdowns = doc.css('#main-sidebar ul.nav-submenu-dropdown')
      expect(dropdowns).not_to be_empty
      dropdowns.each do |ul|
        expect(ul['class'].to_s.split).to include('hidden'),
               "浮层容器 #{ul['id']} 被显性化（.dropdown-container 是绝对定位浮层，只服务 icon-only hover）"
      end
    end
  end

  describe 'AC-011 — 点击二级 = 导航到落地页 + 展开其三级；主区不受影响' do
    it '/admin/admin_users → Users 子树展开，首个三级（Admin Users）为当前项' do
      get '/admin/admin_users'
      expect(response).to have_http_status(:ok)

      users_submenu = doc.at_css('#main-sidebar #nav-submenu-users')
      expect(users_submenu['class'].to_s.split).not_to include('hidden'), '进入子树后三级应展开'

      links = users_submenu.css('a.nav-link').map { |a| a['id'].to_s.sub('nav-link-', '') }
      expect(links).to eq(%w[admin_users invitations roles])
      expect(users_submenu.css('a.nav-link.active').map { |a| a['id'].to_s.sub('nav-link-', '') })
        .to eq(%w[admin_users]), '默认显示第一个三级'

      # 各二级项互不影响（无手风琴）：其它子树的三级仍收起
      expect(doc.at_css('#main-sidebar #nav-submenu-developers')['class'].to_s.split).to include('hidden')

      toggle = doc.at_css('#main-sidebar [data-nav-section-toggle="settings_section"]')
      expect(toggle['data-nav-section-collapsed']).to eq('false')
    end

    it '主区菜单（Orders / Fund）不受分区开关影响' do
      get '/admin/orders'

      %w[orders fund returns].each do |key|
        li = doc.at_xpath("//*[@id='main-sidebar']//a[@id='nav-link-#{key}']/ancestor::li[1]")
        expect(li).to be_present, "主区顶级项 #{key} 未渲染"
        expect(li['class'].to_s.split).not_to include('hidden'), "主区 #{key} 被分区逻辑影响"
      end

      # 主区自身的「激活即展开」语义不变：当前在 Orders → Orders 子菜单展开，Fund 子菜单收起
      expect(doc.at_css('#main-sidebar #nav-submenu-orders')['class'].to_s.split).not_to include('hidden')
      expect(doc.at_css('#main-sidebar #nav-submenu-fund')['class'].to_s.split).to include('hidden')
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
