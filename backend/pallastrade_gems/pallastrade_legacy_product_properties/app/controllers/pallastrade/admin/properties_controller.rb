module PallasTrade
  module Admin
    class PropertiesController < ResourceController
      # 面包屑由导航自动推导（P3）：Products（properties 页面归 products 模块）
      add_breadcrumb PallasTrade.t(:properties), :admin_properties_path

      before_action :add_breadcrumbs

      protected

      def update_turbo_stream_enabled?
        true
      end

      def add_breadcrumbs
        if @property.present? && @property.persisted?
          add_breadcrumb @property.presentation, pallastrade.edit_admin_property_path(@property)
        end
      end

      def permitted_resource_params
        params.require(:property).permit(:name, :presentation, :position, :kind, :display_on)
      end
    end
  end
end
