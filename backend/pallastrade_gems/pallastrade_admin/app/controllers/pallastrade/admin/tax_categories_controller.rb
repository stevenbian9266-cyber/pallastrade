module PallasTrade
  module Admin
    class TaxCategoriesController < ResourceController
      include PallasTrade::Admin::SettingsConcern

      private

      def permitted_resource_params
        params.require(:tax_category).permit(permitted_tax_category_attributes)
      end
    end
  end
end
