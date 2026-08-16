module PallasTrade
  module Admin
    class RefundReasonsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Refund Reasons

      private

      def permitted_resource_params
        params.require(:refund_reason).permit(permitted_refund_reason_attributes)
      end
    end
  end
end
