module PallasTrade
  module Admin
    class RolesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Roles

      # PALLAS-CUSTOM: 角色权限矩阵（P2 权限体系重构）——加载权限上下文
      before_action :load_permission_context, only: %i[new edit]
      create.after :apply_role_permissions
      update.after :apply_role_permissions

      private

      def load_permission_context
        @permission_resources = PallasTrade::PermissionRegistry
        @nav_root_items = PallasTrade.admin.navigation.sidebar&.root_items || []
        @role_permissions = @object&.role_permissions&.to_a || []
      end

      # 保存后重建角色权限（菜单/功能/数据；set 类型不受影响）
      def apply_role_permissions
        return unless params[:role]

        @object.rebuild_role_permissions(
          menu: permission_params[:menu_grants],
          function: permission_params[:function_grants],
          data: permission_params[:data_grants]
        )
      end

      def permission_params
        params.require(:role).permit(
          menu_grants: [],
          function_grants: {},
          data_grants: {}
        )
      end

      helper_method :role_menu_grant?, :role_function_grant?, :role_data_permission

      def role_menu_grant?(nav_key)
        @role_permissions.any? { |rp| rp.permission_type == 'menu' && rp.allowed? && rp.nav_key.to_s == nav_key.to_s }
      end

      def role_function_grant?(resource, action)
        @role_permissions.any? { |rp| rp.permission_type == 'function' && rp.allowed? && rp.resource.to_s == resource.to_s && rp.action.to_s == action.to_s }
      end

      def role_data_permission(resource)
        rp = @role_permissions.find { |row| row.permission_type == 'data' && row.allowed? && row.resource.to_s == resource.to_s }
        rp && { scope: rp.scope, scope_value: rp.scope_value, custom_condition: rp.custom_condition }
      end

      def permitted_resource_params
        params.require(:role).permit(permitted_role_attributes)
      end
    end
  end
end
