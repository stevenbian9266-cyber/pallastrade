# Implementation class for Cancan gem. Permissions are configured through
# permission sets — see PallasTrade::PermissionSets::Base for details on creating
# custom ones.
#
# PALLAS-CUSTOM (2026-08-16 权限体系重构): 后台角色权限由 DB 驱动
# （PallasTrade::RolePermission），取代代码级 `PallasTrade.permissions.assign`
# 的 admin 角色配置。优先级：
#   1. 用户角色存在任何 DB role_permissions → 完全由 DB 驱动（set/function/menu/data）
#   2. 否则回退代码权限集（storefront default 客户等未 DB 配置的场景）
#
# See https://github.com/CanCanCommunity/cancancan for more details.
require 'cancan'

module PallasTrade
  class Ability
    include CanCan::Ability

    # @return [Object] the current user
    attr_reader :user

    # @return [PallasTrade::Store, nil] the current store
    attr_reader :store

    # PALLAS-CUSTOM: 角色菜单权限（nav_key 集合，或 :all = 全部可见）
    attr_reader :menu_permissions

    # PALLAS-CUSTOM: 角色数据权限（{ resource_sym => { scope:, scope_value:, custom_condition: } }）
    attr_reader :data_permissions

    def initialize(user, options = {})
      alias_cancan_delete_action

      @user = user || PallasTrade.user_class.new
      @store = options[:store] || PallasTrade::Current.store
      @menu_permissions = nil
      @data_permissions = {}

      apply_permissions_from_sets
    end

    # PALLAS-CUSTOM: 是否由 DB 权限驱动（2026-08-16）
    def db_driven?
      @db_driven == true
    end

    protected

    def alias_cancan_delete_action
      alias_action :delete, to: :destroy
      alias_action :create, :update, :destroy, to: :modify
    end

    # Applies permissions based on the user's roles and the configured permission sets.
    # DB role_permissions 存在时完全由 DB 驱动；否则回退代码权限集。
    def apply_permissions_from_sets
      role_names = determine_role_names
      return if apply_permissions_from_db(role_names)

      permission_sets = PallasTrade.permissions.permission_sets_for_roles(role_names)
      activate_permission_sets(permission_sets)
    end

    # PALLAS-CUSTOM: 从 DB role_permissions 应用权限（2026-08-16）
    # @return [Boolean] true = DB 驱动（该用户任一角色有权限配置）
    def apply_permissions_from_db(role_names)
      role_permissions = PallasTrade::RolePermission.joins(:role).
                         where(PallasTrade::Role.arel_table[:name].in(role_names.map(&:to_s))).to_a
      return false if role_permissions.empty?

      @db_driven = true

      # set 类型：激活权限集类（保留复杂块逻辑，如 SuperUser）
      role_permissions.select { |rp| rp.permission_type == 'set' && rp.allowed? }.each do |rp|
        klass = safe_permission_set_class(rp.permission_set)
        activate_permission_sets([klass]) if klass
      end

      # data 类型：先记录角色数据权限（function 授予时应用范围条件）
      role_permissions.select { |rp| rp.permission_type == 'data' && rp.allowed? }.each do |rp|
        @data_permissions[rp.resource.to_sym] = {
          scope: rp.scope,
          scope_value: rp.scope_value,
          custom_condition: rp.custom_condition
        }
      end

      # function 类型：resource × action（read/index/show 应用数据范围条件）
      role_permissions.select { |rp| rp.permission_type == 'function' }.each do |rp|
        apply_function_permission(rp)
      end

      # menu 类型：记录角色菜单权限
      menu_rows = role_permissions.select { |rp| rp.permission_type == 'menu' }
      if menu_rows.any?
        if menu_rows.any? { |rp| rp.allowed? && rp.nav_key == 'all' }
          @menu_permissions = :all
        else
          @menu_permissions = menu_rows.filter_map { |rp| rp.allowed? ? rp.nav_key : nil }
        end
      end

      true
    end

    # PALLAS-CUSTOM: function 权限 → can/cannot（2026-08-16）
    # 资源经 PermissionRegistry 解析为模型类（如 orders → PallasTrade::Order），
    # 使 `can?(:read, PallasTrade::Order)` 生效（导航 if: 与控制器 authorize 都用模型类）。
    # 授予任一功能权限时同时授予 `:admin`（admin 面板入口 gate，BaseController#authorize_admin）。
    # read/index/show 授予时叠加数据范围条件（P5：accessible_by 自动生效）。
    def apply_function_permission(rp)
      target = resolve_permission_target(rp.resource)
      action = rp.action.to_sym
      action = :manage if action == :manage

      if rp.allowed?
        if read_action?(action) && (condition = data_condition_for(rp.resource))
          can action, target, condition
        else
          can action, target
        end
        can :admin, target unless action == :admin
      else
        cannot action, target
        cannot :admin, target
      end
    end

    # PALLAS-CUSTOM: 资源名 → 授权主体（2026-08-16）
    # 'all' → :all；注册表有模型类 → 模型类；否则保持资源符号。
    def resolve_permission_target(resource)
      return :all if resource.to_s == 'all'

      entry = PallasTrade::PermissionRegistry[resource]
      entry&.model_class || resource.to_sym
    end

    # PALLAS-CUSTOM: read 系 action（P5 数据权限）
    def read_action?(action)
      %i[read index show].include?(action)
    end

    # PALLAS-CUSTOM: 数据权限条件（P5）
    # 按资源的数据范围生成 CanCanCan 条件哈希，作用于 accessible_by 列表查询：
    #   self    → user_id = 当前用户（仅当注册表声明 user_id 字段）
    #   store   → store_id = scope_value
    #   channel → channel_id = scope_value
    #   custom  → 白名单自定义条件（管理员配置的简单 Hash，如 {"store_id"=>"xxx"}）
    # @param resource [String] 资源名
    # @return [Hash, nil]
    def data_condition_for(resource)
      dp = @data_permissions[resource.to_sym]
      return nil unless dp

      entry = PallasTrade::PermissionRegistry[resource]
      fields = entry&.data_fields || []

      case dp[:scope]
      when 'self'
        return nil unless fields.include?('user_id')

        { user_id: @user&.id }
      when 'store'
        return nil if dp[:scope_value].blank?

        { store_id: dp[:scope_value] }
      when 'channel'
        return nil if dp[:scope_value].blank?

        { channel_id: dp[:scope_value] }
      when 'custom'
        cond = dp[:custom_condition]
        cond if cond.is_a?(Hash) && cond.any?
      end
    end

    def safe_permission_set_class(name)
      return nil if name.blank?

      klass = name.constantize
      klass if klass.is_a?(Class) && klass < PallasTrade::PermissionSets::Base
    rescue NameError
      nil
    end

    # Determines the role names for the current user, scoped to the current
    # store. A +PallasTrade::RoleUser+ is bound to a store via its +store_id+ (set from
    # the role's resource), so a role held on one store does not apply on another,
    # independent of the polymorphic +resource+ the role is attached to.
    #
    # @return [Array<Symbol>] the role names
    def determine_role_names
      return [:default] unless @user.persisted?

      if @user.respond_to?(:role_users)
        role_names = @user.role_users.where(store: @store).
                     joins(:role).
                     pluck("#{PallasTrade::Role.table_name}.name").map(&:to_sym).uniq
        return role_names if role_names.any?
      end

      # Fall back to checking pallastrade_admin? for backward compatibility
      # This supports cases where roles are mocked or admin status is determined differently
      if @user.try(:pallastrade_admin?, @store)
        [:admin]
      else
        [:default]
      end
    end

    # Activates the given permission sets.
    #
    # @param permission_sets [Array<Class>] the permission set classes to activate
    def activate_permission_sets(permission_sets)
      permission_sets.each do |permission_set_class|
        permission_set = permission_set_class.new(self)
        permission_set.activate!
      end
    end
  end
end
