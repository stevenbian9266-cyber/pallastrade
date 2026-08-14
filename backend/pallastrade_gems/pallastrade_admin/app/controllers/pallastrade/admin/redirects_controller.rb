# frozen_string_literal: true

module PallasTrade
  module Admin
    class RedirectsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      private

      def model_class
        PallasTrade::Redirect
      end

      def scope
        current_store.redirects
      end

      def object_name
        'redirect'
      end

      def permitted_resource_params
        params.require(:redirect).permit(permitted_redirect_attributes)
      end

      def location_after_save
        PallasTrade.admin_redirects_path
      end

      def location_after_destroy
        PallasTrade.admin_redirects_path
      end
    end
  end
end
