# frozen_string_literal: true

module PallasTrade
  module Admin
    class RedirectsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      # Load products whose URL (slug) changed, so the redirects page can prompt
      # the user to create a 301 for each old URL. See PallasTrade::ProductUrlChange.
      def index
        super
        @url_changes = PallasTrade::ProductUrlChange.call(current_store)
      end

      # Support pre-filling the form from the URL-change list
      # (/admin/redirects/new?from_path=/products/old&to_path=/products/new).
      def new
        super
        @object.from_path = params[:from_path] if params[:from_path].present?
        @object.to_path = params[:to_path] if params[:to_path].present?
      end

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
