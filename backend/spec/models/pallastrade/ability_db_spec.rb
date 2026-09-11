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
      expect(ability).to be_can(:read, PallasTrade::Order)
      expect(ability).not_to be_can(:create, PallasTrade::Order)
      expect(ability).not_to be_can(:manage, PallasTrade::Product)
    end

    it 'explicit deny (allowed=false) removes a grant' do
      user = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      role = create(:role, name: 'order_partial')
      role.role_permissions.create!(permission_type: 'function', resource: 'orders', action: 'manage', allowed: true)
      role.role_permissions.create!(permission_type: 'function', resource: 'orders', action: 'destroy', allowed: false)
      create(:role_user, user: user, role: role, resource: store, store: store)

      ability = PallasTrade::Ability.new(user, store: store)
      expect(ability).to be_can(:read, PallasTrade::Order)
      expect(ability).not_to be_can(:destroy, PallasTrade::Order)
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

    it 'applies self scope to accessible_by for read (AC-007)' do
      owner = create(:user, email: 'owner@example.com')
      create(:user, email: 'viewer2@example.com')
      order_mine = create(:order, store: store, user: owner)
      order_other = create(:order, store: store, user: create(:user, email: 'other@example.com'))

      viewer_admin = create(:admin_user, email: 'viewer_admin@example.com', password: 'secret', password_confirmation: 'secret',
                                         without_admin_role: true)
      role = create(:role, name: 'self_orders_read')
      role.rebuild_role_permissions(
        function: { orders: ['read'] },
        data: { orders: { scope: 'self' } }
      )
      create(:role_user, user: viewer_admin, role: role, resource: store, store: store)
      # data scope self 用当前 admin 用户 id 过滤（admin 无订单）
      ability = PallasTrade::Ability.new(viewer_admin, store: store)

      visible = PallasTrade::Order.accessible_by(ability, :read)
      expect(visible).not_to include(order_mine)
      expect(visible).not_to include(order_other)
    end

    it 'applies custom condition to accessible_by for read (AC-007)' do
      viewer_admin = create(:admin_user, email: 'custom_admin@example.com', password: 'secret', password_confirmation: 'secret',
                                         without_admin_role: true)
      role = create(:role, name: 'custom_orders')
      role.rebuild_role_permissions(
        function: { orders: ['read'] },
        data: { orders: { scope: 'custom', custom_condition: { 'store_id' => store.id } } }
      )
      create(:role_user, user: viewer_admin, role: role, resource: store, store: store)
      ability = PallasTrade::Ability.new(viewer_admin, store: store)

      visible = PallasTrade::Order.accessible_by(ability, :read)
      expect(visible.to_sql).to include('store_id')
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

  # PRD-20260911-promotions-promo-batch5b-permission-single-source AC-002
  # capability 覆盖多模型：DB 角色拿到 promotions.* 后必须同时能管规则/动作，
  # 否则后台规则弹窗（authorize! PallasTrade::PromotionRule）会被拒绝。
  describe 'capability 多模型覆盖（batch5b）' do
    it 'promotions 授权同时覆盖 Promotion / PromotionRule / PromotionAction' do
      user = create(:admin_user, email: 'promo_mgr@example.com', password: 'secret',
                                 password_confirmation: 'secret', without_admin_role: true)
      role = create(:role, name: 'promotion_manager')
      role.role_permissions.create!(permission_type: 'function', resource: 'promotions', action: 'update', allowed: true)
      create(:role_user, user: user, role: role, resource: store, store: store)

      ability = PallasTrade::Ability.new(user, store: store)

      expect(ability).to be_can(:update, PallasTrade::Promotion)
      expect(ability).to be_can(:update, PallasTrade::PromotionRule)
      expect(ability).to be_can(:update, PallasTrade::PromotionAction)
      expect(ability).to be_can(:admin, PallasTrade::PromotionRule)
      expect(ability).not_to be_can(:update, PallasTrade::Product)
    end

    it 'coupon_codes 是独立 capability，未被授予时不可写' do
      user = create(:admin_user, email: 'promo_reader@example.com', password: 'secret',
                                 password_confirmation: 'secret', without_admin_role: true)
      role = create(:role, name: 'promotion_reader')
      role.role_permissions.create!(permission_type: 'function', resource: 'promotions', action: 'read', allowed: true)
      create(:role_user, user: user, role: role, resource: store, store: store)

      ability = PallasTrade::Ability.new(user, store: store)

      expect(ability).to be_can(:read, PallasTrade::PromotionRule)
      expect(ability).not_to be_can(:update, PallasTrade::CouponCode)

      role.role_permissions.create!(permission_type: 'function', resource: 'coupon_codes', action: 'update', allowed: true)
      ability = PallasTrade::Ability.new(user.reload, store: store)

      expect(ability).to be_can(:update, PallasTrade::CouponCode)
    end

    it '数据范围按模型上卷：规则的读权限经 promotion.store_id 限定到本店' do
      scoped_store = create(:store, code: 'ability_scope_store')
      other_store = create(:store, code: 'ability_scope_other')

      promotion = create(:promotion, store: scoped_store, code: 'ABIL1')
      rule = PallasTrade::Promotion::Rules::Currency.create!(promotion: promotion, preferred_currency: 'USD')
      other_rule = PallasTrade::Promotion::Rules::Currency.create!(
        promotion: create(:promotion, store: other_store, code: 'ABIL2'), preferred_currency: 'USD'
      )

      user = create(:admin_user, email: 'scoped_promo@example.com', password: 'secret',
                                 password_confirmation: 'secret', without_admin_role: true)
      role = create(:role, name: 'scoped_promotion_reader')
      role.rebuild_role_permissions(
        function: { promotions: ['read'] },
        data: { promotions: { scope: 'store', scope_value: scoped_store.id } }
      )
      create(:role_user, user: user, role: role, resource: scoped_store, store: scoped_store)

      ability = PallasTrade::Ability.new(user, store: scoped_store)

      expect(ability).to be_can(:read, rule)
      expect(ability).not_to be_can(:read, other_rule)
    end
  end
end
