# frozen_string_literal: true

require 'rails_helper'

# PRD-20260816-admin-后台可视化菜单配置模块-角色权限体系-菜单-数据-功能权限 AC-008 AC-005 AC-006
# 权限体系重构（P1）：Ability 从 DB role_permissions 驱动，
# admin 角色由 DB seed（set: SuperUser）取代代码级 assign；自定义角色按
# function/menu/data 权限生效；无 DB 配置角色回退代码权限集。
RSpec.describe PallasTrade::Ability do
  let(:store) { create(:store, code: 'ability_db_test') }

  describe 'admin 角色（DB seed SuperUser）' do
    it 'grants manage :all via seeded set permission (AC-008)' do
      admin_user = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      admin_role = PallasTrade::Role.default_admin_role
      create(:role_user, user: admin_user, role: admin_role, resource: store, store: store)

      ability = PallasTrade::Ability.new(admin_user, store: store)
      expect(ability.db_driven?).to be(true)
      expect(ability).to be_can(:manage, :all)
      expect(ability).to be_can(:read, PallasTrade::Order)
      expect(ability).to be_can(:update, PallasTrade::Product)
    end
  end

  describe '自定义角色（DB function 权限）' do
    it 'grants only configured resource:action (AC-006)' do
      user = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      role = create(:role, name: 'order_viewer')
      role.role_permissions.create!(permission_type: 'function', resource: 'orders', action: 'read', allowed: true)
      create(:role_user, user: user, role: role, resource: store, store: store)

      ability = PallasTrade::Ability.new(user, store: store)
      expect(ability.db_driven?).to be(true)
      expect(ability).to be_can(:read, :orders)
      expect(ability).not_to be_can(:create, :orders)
      expect(ability).not_to be_can(:manage, :products)
    end

    it 'explicit deny (allowed=false) removes a grant' do
      user = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      role = create(:role, name: 'order_partial')
      role.role_permissions.create!(permission_type: 'function', resource: 'orders', action: 'manage', allowed: true)
      role.role_permissions.create!(permission_type: 'function', resource: 'orders', action: 'destroy', allowed: false)
      create(:role_user, user: user, role: role, resource: store, store: store)

      ability = PallasTrade::Ability.new(user, store: store)
      expect(ability).to be_can(:read, :orders)
      expect(ability).not_to be_can(:destroy, :orders)
    end
  end

  describe 'menu 权限' do
    it 'exposes role menu grants via menu_permissions (AC-005)' do
      user = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      role = create(:role, name: 'orders_only')
      role.role_permissions.create!(permission_type: 'menu', nav_key: 'orders', allowed: true)
      role.role_permissions.create!(permission_type: 'menu', nav_key: 'orders_to_fulfill', allowed: true)
      create(:role_user, user: user, role: role, resource: store, store: store)

      ability = PallasTrade::Ability.new(user, store: store)
      expect(ability.menu_permissions).to contain_exactly('orders', 'orders_to_fulfill')
    end

    it 'exposes :all when a role has menu permission for :all' do
      user = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      role = create(:role, name: 'all_menu')
      role.role_permissions.create!(permission_type: 'menu', nav_key: 'all', allowed: true)
      create(:role_user, user: user, role: role, resource: store, store: store)

      ability = PallasTrade::Ability.new(user, store: store)
      expect(ability.menu_permissions).to be(:all)
    end
  end

  describe 'data 权限' do
    it 'exposes resource data scope (AC-007)' do
      user = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      role = create(:role, name: 'self_orders')
      role.role_permissions.create!(permission_type: 'data', resource: 'orders', scope: 'self', allowed: true)
      create(:role_user, user: user, role: role, resource: store, store: store)

      ability = PallasTrade::Ability.new(user, store: store)
      expect(ability.data_permissions[:orders]).to eq({ scope: 'self', scope_value: nil, custom_condition: nil })
    end
  end

  describe '无 DB 配置角色（回退代码权限集）' do
    it 'falls back to code permission sets for unconfigured roles (AC-008)' do
      user = create(:user, email: 'guest@example.com')
      ability = PallasTrade::Ability.new(user, store: store)
      # default 客户角色无 DB role_permissions → 回退 DefaultCustomer
      expect(ability.db_driven?).to be(false)
      expect(ability).to be_can(:read, PallasTrade::Product)
    end
  end
end
