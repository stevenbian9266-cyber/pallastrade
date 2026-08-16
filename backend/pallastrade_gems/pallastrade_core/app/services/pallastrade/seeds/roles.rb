module PallasTrade
  module Seeds
    class Roles
      prepend PallasTrade::ServiceModule::Base

      # PALLAS-CUSTOM: 权限体系重构（2026-08-16）——admin 角色权限由 DB 驱动。
      # 确保 admin 角色存在并 seed 其 SuperUser 权限集（set 类型），
      # 取代代码级 `PallasTrade.permissions.assign(:admin, [SuperUser])`。
      def call
        role = PallasTrade::Role.where(name: 'admin').first_or_create!
        seed_super_user_permission(role)
        role
      end

      private

      def seed_super_user_permission(role)
        return if role.role_permissions.set.exists?(permission_set: 'PallasTrade::PermissionSets::SuperUser')

        role.role_permissions.find_or_create_by!(
          permission_type: 'set',
          permission_set: 'PallasTrade::PermissionSets::SuperUser',
          allowed: true
        )
      end
    end
  end
end
