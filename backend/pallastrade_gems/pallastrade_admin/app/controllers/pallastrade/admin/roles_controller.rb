module PallasTrade
  module Admin
    class RolesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      add_breadcrumb PallasTrade.t(:roles), :admin_roles_path

      private

      def permitted_resource_params
        params.require(:role).permit(permitted_role_attributes)
      end
    end
  end
end
