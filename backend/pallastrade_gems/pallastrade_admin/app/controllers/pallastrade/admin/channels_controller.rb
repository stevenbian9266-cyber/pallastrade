module PallasTrade
  module Admin
    class ChannelsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      add_breadcrumb PallasTrade.t(:channels), :admin_channels_path

      private

      def permitted_resource_params
        params.require(:channel).permit(permitted_channel_attributes)
      end
    end
  end
end
