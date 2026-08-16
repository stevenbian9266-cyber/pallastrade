# frozen_string_literal: true

require 'rails_helper'

# PRD-20260816-admin-后台可视化菜单配置模块-角色权限体系-菜单-数据-功能权限 AC-001 AC-002 AC-003
# 可视化菜单配置模块（P4）：全局/店铺作用域、显隐/改名/排序、自定义菜单项、即时生效。
RSpec.describe 'Admin menu configuration module', type: :request do
  let(:store) { create(:store, code: 'menu_config_test') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::OrdersController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::MenuConfigsController).to receive(:current_store).and_return(store)
  end

  # PRD-... AC-001
  it 'renders the menu config page with tree + scope toggle' do
    get '/admin/menu_configs'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.menu_configs.title'))
    expect(response.body).to include(PallasTrade.t('admin.menu_configs.global_scope'))
    expect(response.body).to include(PallasTrade.t('admin.menu_configs.store_scope'))
    expect(response.body).to include(PallasTrade.t(:orders))
    expect(response.body).to include(PallasTrade.t(:products))
  end

  # PRD-... AC-002 / AC-003
  it 'hides a menu + adds a custom item (global) and applies immediately to the sidebar' do
    post '/admin/menu_configs', params: {
      scope: 'global',
      items: { blog: { visible: '0' }, home: { visible: '1' } },
      custom_items: { '0' => { label: 'My Ext Link', url: 'https://example.com', icon: 'external-link', open_in_new_tab: '1' } }
    }
    expect(response).to have_http_status(:redirect)
    follow_redirect! if response.status == 302

    # 保存后侧边栏即时生效：Blog 隐藏，自定义项显示
    get '/admin/orders'
    expect(response).to have_http_status(:ok)
    sidebar_el = Nokogiri::HTML(response.body).at_css('#main-sidebar')
    sidebar = sidebar_el ? sidebar_el.text.to_s : ''
    expect(sidebar).to include('My Ext Link')
    expect(sidebar).not_to include(PallasTrade.t(:blog))

    # 全局配置持久化
    cfg = PallasTrade::MenuConfig.global.find_by(nav_key: 'blog')
    expect(cfg.visible).to be(false)
    expect(PallasTrade::MenuConfig.global.custom.exists?(label: 'My Ext Link')).to be(true)
  end

  # PRD-... AC-002（店铺覆盖）
  it 'persists store-scoped overrides separately from global' do
    PallasTrade::MenuConfig.create!(store: nil, item_type: 'default', nav_key: 'blog', visible: false)

    post '/admin/menu_configs', params: {
      scope: 'store',
      items: { blog: { visible: '1' }, home: { visible: '1' } },
      custom_items: { '0' => { label: '', url: '' } }
    }
    expect(response).to have_http_status(:redirect)

    store_cfg = PallasTrade::MenuConfig.for_store(store).find_by(nav_key: 'blog')
    expect(store_cfg.visible).to be(true)
    # 全局未被覆盖为 show（店铺覆盖独立）
    global_cfg = PallasTrade::MenuConfig.global.find_by(nav_key: 'blog')
    expect(global_cfg.visible).to be(false)
  end
end
