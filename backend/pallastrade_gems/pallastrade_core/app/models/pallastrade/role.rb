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
  end
end
