module PallasTrade
  module Admin
    class TaxonomiesController < ResourceController
      # 面包屑由导航自动推导（P3）：Products → Taxonomies；add_breadcrumbs 追加名称

      before_action :add_breadcrumbs

      private

      def location_after_save
        PallasTrade.admin_taxonomy_path(@taxonomy)
      end

      def add_breadcrumbs
        if @taxonomy.present? && @taxonomy.persisted?
          add_breadcrumb @taxonomy.name, PallasTrade.admin_taxonomy_path(@taxonomy)
        end
      end

      def permitted_resource_params
        params.require(:taxonomy).permit(permitted_taxonomy_attributes)
      end

      def update_turbo_stream_enabled?
        true
      end
    end
  end
end
