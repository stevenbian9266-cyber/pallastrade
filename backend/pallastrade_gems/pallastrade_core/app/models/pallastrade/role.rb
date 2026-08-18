module PallasTrade
  class Role < PallasTrade.base_class
    has_prefix_id :role

    include PallasTrade::UniqueName

    ADMIN_ROLE = 'admin'

    #
    # Associations
    #
    has_many :role_users, class_name: 'PallasTrade::RoleUser', dependent: :destroy
    has_many :users, through: :role_users, source: :user, source_type: PallasTrade.user_class.to_s
    has_many :admin_users, through: :role_users, source: :user, source_type: PallasTrade.admin_user_class.to_s
    has_many :invitations, class_name: 'PallasTrade::Invitation', dependent: :destroy
    # PALLAS-CUSTOM: 角色权限（2026-08-16 权限体系重构）
    has_many :role_permissions, class_name: 'PallasTrade::RolePermission', dependent: :destroy

    #
    # Scopes
    #
    scope :admin, -> { where(name: ADMIN_ROLE) }

    #
    # Class Methods
    #
    # PALLAS-CUSTOM: 权限体系重构（2026-08-16）——admin 角色权限由 DB 驱动，
    # 获取 admin 角色时同时确保其 SuperUser 权限集存在（取代代码级
    # `PallasTrade.permissions.assign(:admin, [SuperUser])`）。
    def self.default_admin_role
      role = find_or_create_by(name: ADMIN_ROLE)
      role.ensure_super_user_permission
      role
    end

    # PALLAS-CUSTOM: 确保 admin 角色持有 SuperUser DB 权限（set 类型）
    def ensure_super_user_permission
      return unless name == ADMIN_ROLE

      role_permissions.set.where(permission_set: 'PallasTrade::PermissionSets::SuperUser', allowed: true).first_or_create!
    end

    # PALLAS-CUSTOM: 重建菜单/功能/数据权限（2026-08-16 权限体系重构）
    # 由 Roles 编辑页提交的勾选/选择重建；set 类型（如 admin SuperUser）不受影响。
    # @param menu [Array<String>] 授权的导航项 key（菜单权限）
    # @param function [Hash<String, Array<String>>] resource => actions（功能权限）
    # @param data [Hash<String, Hash>] resource => { scope:, scope_value:, custom_condition: }（数据权限）
    def rebuild_role_permissions(menu: nil, function: nil, data: nil)
      role_permissions.transaction do
        role_permissions.where(permission_type: %w[menu function data]).destroy_all

        Array(menu).uniq.compact.each do |nav_key|
          role_permissions.create!(permission_type: 'menu', nav_key: nav_key.to_s, allowed: true)
        end

        (function || {}).each do |resource, actions|
          Array(actions).compact.uniq.each do |action|
            role_permissions.create!(permission_type: 'function', resource: resource.to_s, action: action.to_s, allowed: true)
          end
        end

        (data || {}).each do |resource, cfg|
          cfg = cfg.to_h.symbolize_keys
          next if cfg[:scope].blank?

          role_permissions.create!(
            permission_type: 'data',
            resource: resource.to_s,
            scope: cfg[:scope].to_s,
            scope_value: cfg[:scope_value].presence,
            custom_condition: cfg[:custom_condition].presence,
            allowed: true
          )
        end
      end
      true
    end
  end
end
