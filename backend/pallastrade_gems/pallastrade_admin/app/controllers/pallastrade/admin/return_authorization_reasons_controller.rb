module PallasTrade
  module Admin
    class ReturnAuthorizationReasonsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Return Authorization Reasons

      private

      def permitted_resource_params
        params.require(:return_authorization_reason).permit(permitted_return_authorization_reason_attributes)
      end
    end
  end
end
