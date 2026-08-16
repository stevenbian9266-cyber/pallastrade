module PallasTrade
  module Admin
    class ChannelsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      # 面包屑由导航配置自动推导（P5）：Settings > Sales channels

      private

      def permitted_resource_params
        params.require(:channel).permit(permitted_channel_attributes)
      end
    end
  end
end
