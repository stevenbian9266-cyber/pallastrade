module PallasTrade
  module Admin
    class TaxonomiesController < ResourceController
      include ProductsBreadcrumbConcern
      add_breadcrumb PallasTrade.t(:taxonomies), :admin_taxonomies_path

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
