module PallasTrade
  module Admin
    module SettingsConcern
      extend ActiveSupport::Concern

      included do
        before_action :set_settings_area_flag
      end

      def choose_layout
        return 'turbo_rails/frame' if turbo_frame_request?

        # P4 单一布局：设置区复用主布局（顶部 header 面包屑 + main 内页面头/tabs）
        'pallastrade/admin'
      end

      private

      def set_settings_area_flag
        @settings_area = true
      end
    end
  end
end
