module PallasTrade
  module Admin
    class ShippingCategoriesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Shipping Categories

      private

      def permitted_resource_params
        params.require(:shipping_category).permit(permitted_shipping_category_attributes)
      end
    end
  end
end
