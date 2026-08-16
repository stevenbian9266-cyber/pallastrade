# frozen_string_literal: true

module PallasTrade
  module Admin
    # PALLAS-CUSTOM: 可视化菜单配置模块（P4 权限体系重构）
    # 基于导航配置文件默认树的覆盖层：显隐 / 改名 / 排序 / 自定义菜单项，
    # 全局（store_id nil）或当前店铺作用域，DB 存储即时生效。
    class MenuConfigsController < BaseController
      include PallasTrade::Admin::SettingsConcern

      # GET /admin/menu_configs
      def index
        load_menu_config_context
      end

      # POST /admin/menu_configs
      def update
        scope = params[:scope].to_s == 'store' ? :store : :global
        store = scope == :store ? current_store : nil

        rebuild_configs(store)

        flash[:success] = PallasTrade.t('admin.menu_configs.saved')
        redirect_to PallasTrade.admin_menu_configs_path(scope: params[:scope]), status: :see_other
      rescue ActiveRecord::RecordInvalid => e
        flash[:error] = e.message
        load_menu_config_context
        render :index, status: :unprocessable_content
      end

      private

      helper_method :config_for, :custom_configs

      def load_menu_config_context
        @scope = params[:scope].to_s == 'store' ? :store : :global
        @store_scope = @scope == :store
        @nav_root_items = PallasTrade.admin.navigation.sidebar&.root_items || []
        @configs = PallasTrade::MenuConfig.global + PallasTrade::MenuConfig.for_store(current_store)
      end

      # 视图辅助：返回某 nav_key 的覆盖配置（当前作用域）
      def config_for(nav_key)
        @configs.find { |cfg| cfg.item_type == 'default' && cfg.nav_key.to_s == nav_key.to_s }
      end

      # 视图辅助：当前作用域的自定义菜单项
      def custom_configs
        @custom_configs ||= @configs.select { |cfg| cfg.item_type == 'custom' }
      end

      # 重建（销毁 + 重建）指定作用域的菜单配置
      def rebuild_configs(store)
        PallasTrade::MenuConfig.transaction do
          PallasTrade::MenuConfig.where(store: store).destroy_all

          items_params.each do |nav_key, cfg|
            # 未勾选时 hidden 字段传 visible=0；只创建有实际覆盖的行
            next unless cfg[:visible] == '1' || cfg[:visible] == '0' || cfg[:label].present? || cfg[:position].present?

            PallasTrade::MenuConfig.create!(
              store: store,
              item_type: 'default',
              nav_key: nav_key,
              visible: cfg[:visible] == '1',
              label: cfg[:label].presence,
              position: cfg[:position].presence&.to_i
            )
          end

          custom_items_params.each do |_idx, cfg|
            next if cfg[:_destroy].present? && cfg[:_destroy] != 'false'
            next if cfg[:label].blank? && cfg[:url].blank?

            PallasTrade::MenuConfig.create!(
              store: store,
              item_type: 'custom',
              nav_key: cfg[:nav_key].presence || "custom_#{SecureRandom.hex(4)}",
              label: cfg[:label],
              url: cfg[:url],
              icon: cfg[:icon].presence,
              parent_key: cfg[:parent_key].presence,
              position: cfg[:position].presence&.to_i,
              open_in_new_tab: cfg[:open_in_new_tab] == '1'
            )
          end
        end
      end

      def items_params
        params.fetch(:items, {}).to_unsafe_h
      end

      def custom_items_params
        params.fetch(:custom_items, {}).to_unsafe_h
      end
    end
  end
end
