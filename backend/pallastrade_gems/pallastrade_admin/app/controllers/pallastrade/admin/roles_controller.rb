module PallasTrade
  module Admin
    class RolesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Roles

      private

      def permitted_resource_params
        params.require(:role).permit(permitted_role_attributes)
      end
    end
  end
end
