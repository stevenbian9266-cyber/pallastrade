# frozen_string_literal: true

require 'rails_helper'

# PRD-20260817-admin-菜单配置收敛-结构代码化-可视化只读展示-权限配置依据
# AC-001~004 / AC-006：菜单配置页只读可视化；移除写能力与自定义项；
# 历史 MenuConfig 覆盖不再影响渲染；侧边栏 = 代码默认树。
RSpec.describe 'Admin menu configuration module (read-only)', type: :request do
  let(:store) { create(:store, code: 'menu_config_readonly_test') }
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

  # PRD-... AC-001 / AC-002
  it 'renders the menu config page as a read-only tree with no edit controls' do
    get '/admin/menu_configs'
    expect(response).to have_http_status(:ok)

    body = response.body
    # 只读说明 + 完整菜单树（一级 + 二级）
    expect(body).to include(PallasTrade.t('admin.menu_configs.title'))
    expect(body).to include(PallasTrade.t('admin.menu_configs.readonly_help'))
    expect(body).to include(PallasTrade.t(:orders))
    expect(body).to include(PallasTrade.t('admin.orders.all_orders'))
    expect(body).to include(PallasTrade.t(:products))
    expect(body).to include(PallasTrade.t('admin.products.products_list'))

    # 无任何编辑控件：无提交表单 / checkbox / 文本输入 / 数字输入 / 自定义菜单区块
    expect(body).not_to include('action="/admin/menu_configs"')
    expect(body).not_to include('type="checkbox"')
    expect(body).not_to include('type="text"')
    expect(body).not_to include('type="number"')
    expect(body).not_to include('custom_items')
  end

  # PRD-... AC-004：写路由已移除（无删除/添加二级菜单/保存入口）
  it 'removes the write route (POST /admin/menu_configs is not routed)' do
    post '/admin/menu_configs', params: { scope: 'global' }
    expect([404, 405]).to include(response.status)
  end

  # PRD-... AC-003：历史 MenuConfig 覆盖（隐藏/自定义项）不再影响侧边栏渲染
  it 'ignores historical MenuConfig overrides and renders the code-defined sidebar' do
    # 历史覆盖：隐藏 blog + 一条自定义外链
    PallasTrade::MenuConfig.create!(store: nil, item_type: 'default', nav_key: 'blog', visible: false)
    PallasTrade::MenuConfig.create!(
      store: nil, item_type: 'custom', nav_key: 'custom_legacy',
      label: 'Legacy Custom Link', url: 'https://example.com/legacy'
    )

    get '/admin/orders'
    expect(response).to have_http_status(:ok)

    sidebar_el = Nokogiri::HTML(response.body).at_css('#main-sidebar')
    sidebar = sidebar_el ? sidebar_el.text.to_s : ''

    # blog 按代码默认树显示（覆盖失效）
    expect(sidebar).to include(PallasTrade.t(:blog))
    # 历史自定义项不再渲染
    expect(sidebar).not_to include('Legacy Custom Link')
  end
end
