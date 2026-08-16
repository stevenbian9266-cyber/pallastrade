module PallasTrade
  module Admin
    class ReimbursementTypesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      add_breadcrumb PallasTrade.t(:reimbursement_types), :admin_reimbursement_types_path

      private

      def permitted_resource_params
        params.require(:reimbursement_type).permit(permitted_reimbursement_type_attributes)
      end
    end
  end
end
