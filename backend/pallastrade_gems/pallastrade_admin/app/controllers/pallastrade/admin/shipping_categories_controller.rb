module PallasTrade
  module Admin
    class ShippingCategoriesController < ResourceController
      include PallasTrade::Admin::SettingsConcern

      private

      def permitted_resource_params
        params.require(:shipping_category).permit(permitted_shipping_category_attributes)
      end
    end
  end
end
