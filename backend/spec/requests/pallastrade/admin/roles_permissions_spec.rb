# frozen_string_literal: true

require 'rails_helper'

# PRD-20260816-admin-后台可视化菜单配置模块-角色权限体系-菜单-数据-功能权限 AC-004 AC-005 AC-006 AC-007
# 角色权限矩阵 UI（P2）：Roles 编辑页渲染 菜单/功能/数据 三 tab，
# 保存后权限持久化并由 Ability 生效。
RSpec.describe 'Admin roles permissions matrix', type: :request do
  let(:store) { create(:store, code: 'roles_perm_test') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::RolesController).to receive(:current_store).and_return(store)
  end

  # PRD-... AC-004
  it 'renders the permissions matrix tabs on the role edit page' do
    role = create(:role, name: 'support')
    get "/admin/roles/#{role.to_param}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.roles.menu_permissions'))
    expect(response.body).to include(PallasTrade.t('admin.roles.function_permissions'))
    expect(response.body).to include(PallasTrade.t('admin.roles.data_permissions'))
  end

  # PRD-... AC-004 / AC-006
  it 'persists function + menu permissions on update and they drive the ability' do
    role = create(:role, name: 'order_viewer')
    # 测试环境 host 不匹配触发 OpenRedirectError（环境 default_url host=localhost:3000）
    allow_any_instance_of(PallasTrade::Admin::RolesController).to receive(:location_after_save).and_return('/admin/roles')

    patch "/admin/roles/#{role.to_param}", params: {
      role: {
        name: 'order_viewer',
        menu_grants: ['orders', 'orders_to_fulfill'],
        function_grants: { orders: ['read'] },
        data_grants: { orders: { scope: 'self' } }
      }
    }

    expect(response).to have_http_status(:redirect)
    role.reload
    expect(role.role_permissions.menu.map(&:nav_key)).to contain_exactly('orders', 'orders_to_fulfill')
    expect(role.role_permissions.function.pluck(:resource, :action)).to include(['orders', 'read'])
    data = role.role_permissions.data.first
    expect(data.resource).to eq('orders')
    expect(data.scope).to eq('self')
  end

  # PRD-... AC-005
  it 'limits sidebar menus to the role menu permissions (menu permission enforcement)' do
    viewer = create(:admin_user, email: 'viewer@example.com', password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    role = create(:role, name: 'orders_only')
    role.rebuild_role_permissions(menu: ['orders', 'orders_to_fulfill', 'draft_orders'])
    create(:role_user, user: viewer, role: role, resource: store, store: store)

    ability = PallasTrade::Ability.new(viewer, store: store)
    expect(ability.menu_permissions).to contain_exactly('orders', 'orders_to_fulfill', 'draft_orders')
  end

  # PRD-... AC-006
  it 'enforces function permission (read-only orders)' do
    viewer = create(:admin_user, email: 'reader@example.com', password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    role = create(:role, name: 'reader')
    role.rebuild_role_permissions(function: { orders: ['read'] })
    create(:role_user, user: viewer, role: role, resource: store, store: store)

    ability = PallasTrade::Ability.new(viewer, store: store)
    expect(ability).to be_can(:read, PallasTrade::Order)
    expect(ability).not_to be_can(:create, PallasTrade::Order)
    expect(ability).not_to be_can(:manage, PallasTrade::Product)
  end

  # PRD-... AC-005 / AC-010
  it 'renders only menu-granted items in the sidebar for a restricted role' do
    viewer = create(:admin_user, email: 'menus@example.com', password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    role = create(:role, name: 'orders_only')
    role.rebuild_role_permissions(
      menu: ['orders', 'orders_to_fulfill', 'draft_orders'],
      function: { orders: ['read'] }
    )
    create(:role_user, user: viewer, role: role, resource: store, store: store)
    viewer_ability = PallasTrade::Ability.new(viewer, store: store)
    allow_any_instance_of(PallasTrade::Admin::OrdersController).to receive(:current_ability).and_return(viewer_ability)
    allow_any_instance_of(PallasTrade::Admin::OrdersController).to receive(:current_store).and_return(store)

    get '/admin/orders'
    warn "DEBUG LOCATION: #{response.location.inspect}" if response.status == 302
    expect(response).to have_http_status(:ok)
    sidebar = Nokogiri::HTML(response.body).at_css('#main-sidebar')&.text.to_s

    # 授权菜单显示
    expect(sidebar).to include(PallasTrade.t(:orders))
    expect(sidebar).to include(PallasTrade.t('admin.orders.orders_to_fulfill'))
    # 未授权子项（All Orders）与未授权菜单隐藏
    expect(sidebar).not_to include(PallasTrade.t('admin.orders.all_orders'))
    expect(sidebar).not_to include(PallasTrade.t(:products))
    expect(sidebar).not_to include(PallasTrade.t(:customers))
    expect(sidebar).not_to include(PallasTrade.t(:developers))
  end
end
