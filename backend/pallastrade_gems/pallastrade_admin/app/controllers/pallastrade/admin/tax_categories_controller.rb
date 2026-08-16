module PallasTrade
  module Admin
    class TaxCategoriesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Tax Categories

      private

      def permitted_resource_params
        params.require(:tax_category).permit(permitted_tax_category_attributes)
      end
    end
  end
end
