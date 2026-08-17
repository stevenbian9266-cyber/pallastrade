# frozen_string_literal: true

module PallasTrade
  module Admin
    # PALLAS-CUSTOM: 菜单配置只读可视化（2026-08-17 方向收敛）
    # 菜单结构由代码导航配置（pallastrade_admin_navigation.rb）定义，本页仅只读展示
    # 完整导航树（一级/二级、landing 落地、图标、URL），让用户直观感受后台菜单结构；
    # 权限配置依据在 Roles 页「菜单权限」树状勾选（与本站同一导航树）。
    class MenuConfigsController < BaseController
      include PallasTrade::Admin::SettingsConcern

      # GET /admin/menu_configs
      def index
        @nav_root_items = PallasTrade.admin.navigation.sidebar&.root_items || []
      end
    end
  end
end
