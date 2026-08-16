module PallasTrade
  module Admin
    class DigitalAssetsController < ResourceController
      belongs_to 'pallastrade/product', find_by: :slug

      # 面包屑由导航自动推导（P3）：Products；add_breadcrumbs 追加产品名 + Digital Assets

      before_action :add_breadcrumbs

      private

      def model_class
        PallasTrade::Digital
      end

      def scope
        parent.digitals.accessible_by(current_ability, :index)
      end

      def collection_url
        PallasTrade.admin_product_digital_assets_path(parent)
      end

      def build_resource
        parent.digitals.build
      end

      def find_resource
        parent.digitals.find_by_prefix_id!(params[:id])
      end

      def create_turbo_stream_enabled?
        @object.errors.any?
      end

      def update_turbo_stream_enabled?
        @object.errors.any?
      end

      def location_after_save
        PallasTrade.admin_product_digital_assets_path(parent)
      end

      def permitted_resource_params
        params.require(:digital_asset).permit(permitted_digital_attributes)
      end

      def add_breadcrumbs
        add_breadcrumb @product.name, PallasTrade.edit_admin_product_path(@product)
        add_breadcrumb PallasTrade.t(:digital_assets), PallasTrade.admin_product_digital_assets_path(@product)
      end
    end
  end
end
