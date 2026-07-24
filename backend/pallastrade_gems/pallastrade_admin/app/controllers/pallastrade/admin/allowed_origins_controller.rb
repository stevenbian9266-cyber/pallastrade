# frozen_string_literal: true

module PallasTrade
  module Admin
    class AllowedOriginsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      include PallasTrade::Admin::TableConcern

      private

      def model_class
        PallasTrade::AllowedOrigin
      end

      def scope
        current_store.allowed_origins
      end

      def object_name
        'allowed_origin'
      end

      def permitted_resource_params
        params.require(:allowed_origin).permit(permitted_allowed_origin_attributes)
      end

      def location_after_save
        PallasTrade.admin_allowed_origins_path
      end

      def location_after_destroy
        PallasTrade.admin_allowed_origins_path
      end
    end
  end
end
