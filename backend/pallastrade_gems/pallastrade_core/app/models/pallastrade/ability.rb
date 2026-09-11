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
        @menu_permissions = if menu_rows.any? { |rp| rp.allowed? && rp.nav_key == 'all' }
                              :all
                            else
                              menu_rows.filter_map { |rp| rp.allowed? ? rp.nav_key : nil }
                            end
      end

      true
    end

    # PALLAS-CUSTOM: function 权限 → can/cannot（2026-08-16）
    # 资源经 PermissionRegistry 解析为模型类（如 orders → PallasTrade::Order），
    # 使 `can?(:read, PallasTrade::Order)` 生效（导航 if: 与控制器 authorize 都用模型类）。
    #
    # PALLAS-CUSTOM (2026-09-11, PRD-20260911-promotions-promo-batch5b): 一个 capability
    # 可覆盖多个模型（如 promotions → Promotion / PromotionRule / PromotionAction），
    # 对每个模型应用同一 grant；数据范围条件按模型分别派生（模型无该列时经 belongs_to 上卷）。
    def apply_function_permission(rp)
      action = rp.action.to_sym

      resolve_permission_targets(rp.resource).each do |target|
        condition = read_action?(action) ? data_condition_for(rp.resource, target) : nil

        if rp.allowed?
          if condition
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
    end

    # PALLAS-CUSTOM: 资源名 → 授权主体集合（2026-08-16 / 多模型覆盖 2026-09-11）
    # 'all' → [:all]；注册表声明了覆盖模型 → 全部模型；否则保持资源符号。
    def resolve_permission_targets(resource)
      return [:all] if resource.to_s == 'all'

      entry = PallasTrade::PermissionRegistry[resource]
      Array(entry&.models).presence || [entry&.model_class || resource.to_sym]
    end

    # 向后兼容：单目标解析（取第一个主体）。
    def resolve_permission_target(resource)
      resolve_permission_targets(resource).first
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
    #
    # PALLAS-CUSTOM (batch5b): 传入 `model:` 时按该模型派生；覆盖模型没有该列时
    # 经 belongs_to 上卷（PromotionRule → promotion.store_id），避免跨店越权或 SQL 报错。
    # @param resource [String, Symbol] 资源名
    # @param model [Class, nil] 目标模型（nil = 资源主模型）
    # @return [Hash, nil]
    def data_condition_for(resource, model = nil)
      dp = @data_permissions[resource.to_sym]
      return nil unless dp

      entry = PallasTrade::PermissionRegistry[resource]
      fields = entry&.data_fields || []

      case dp[:scope]
      when 'self'
        return nil unless fields.include?('user_id')

        scope_condition_for(model || entry&.model_class, :user_id, @user&.id)
      when 'store'
        return nil if dp[:scope_value].blank?

        scope_condition_for(model || entry&.model_class, :store_id, dp[:scope_value])
      when 'channel'
        return nil if dp[:scope_value].blank?

        scope_condition_for(model || entry&.model_class, :channel_id, dp[:scope_value])
      when 'custom'
        cond = dp[:custom_condition]
        cond if cond.is_a?(Hash) && cond.any?
      end
    end

    # 模型自身有列 → 直接条件；否则找 belongs_to 关联持有该列的模型（如
    # PromotionRule → promotion.store_id）；都没有时保持原条件（查询期显式报错，
    # 而不是退化为无条件放行）。
    def scope_condition_for(model, field, value)
      return { field => value } if model.nil? || !model.respond_to?(:column_names)

      if model.column_names.include?(field.to_s)
        { field => cast_column_value(model, field, value) }
      else
        association = belongs_to_owner(model, field)
        return { field => value } unless association

        { association.name => { field => cast_column_value(association.klass, field, value) } }
      end
    end

    def belongs_to_owner(model, field)
      model.reflect_on_all_associations(:belongs_to).find do |candidate|
        candidate.klass.respond_to?(:column_names) && candidate.klass.column_names.include?(field.to_s)
      rescue StandardError
        false
      end
    end

    # role_permissions.scope_value 是字符串列；CanCan 条件按模型属性比较，
    # 需要按目标列类型转换（store_id 是整数列 → "5" 必须变 5，否则永远不匹配）。
    def cast_column_value(model, field, value)
      model.type_for_attribute(field.to_s).cast(value)
    rescue StandardError
      value
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
