module PallasTrade
  module Admin
    class ReimbursementTypesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Reimbursement Types

      private

      def permitted_resource_params
        params.require(:reimbursement_type).permit(permitted_reimbursement_type_attributes)
      end
    end
  end
end
