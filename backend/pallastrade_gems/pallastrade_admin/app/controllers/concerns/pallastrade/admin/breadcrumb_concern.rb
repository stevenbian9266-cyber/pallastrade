module PallasTrade
  module Admin
    # PALLAS-CUSTOM: 面包屑自动推导（P3 导航架构重构）
    #
    # 主区(sidebar)页面不再需要手写 breadcrumb concern / add_breadcrumb：
    # 请求路径 → 导航配置 → 自动 图标 + 父级 + 子级 面包屑。
    # 设置区(settings)保留现有控制器手写 crumb（settings nav 为 section 级，
    # 归 P4 section/tabs 统一阶段再移除）。
    module BreadcrumbConcern
      extend ActiveSupport::Concern

      included do
        class_attribute :breadcrumb_icon
        before_action :add_breadcrumb_icon_instance_var
        before_action :derive_breadcrumbs_from_navigation
      end

      class_methods do
        def add_breadcrumb_icon(icon_name)
          self.breadcrumb_icon = icon_name
        end
      end

      def add_breadcrumb_icon_instance_var
        @breadcrumb_icon = self.class.breadcrumb_icon
      end

      private

      # PALLAS-CUSTOM: settings-area detection that is safe at derive time.
      # `SettingsConcern#set_settings_area_flag` runs as a subclass before_action
      # AFTER this concern's derive, so `@settings_area` alone is unreliable —
      # use the class-level include (immune to callback ordering) as the primary
      # signal, falling back to the flag for edge cases.
      def settings_controller?
        @settings_area.present? ||
          self.class.include?(PallasTrade::Admin::SettingsConcern)
      end

      # Derive breadcrumbs from the sidebar navigation config for the current
      # request path. Skips the settings area (its nav items are section-level
      # and will be unified in P4). Object pages append their own crumb via
      # controller before_action (e.g. add_breadcrumb_for_product).
      # Also records @navigation_page_title (deepest matched item label) so
      # views without content_for :page_title get an automatic page header.
      def derive_breadcrumbs_from_navigation
        return unless respond_to?(:add_breadcrumb, true)
        return if settings_controller?

        chain = PallasTrade.admin.navigation.sidebar&.find_breadcrumb_chain(request.path, self)
        return if chain.blank?

        # P4 page_title fallback：最深匹配项 label 作为页面头默认标题
        @navigation_page_title ||= chain.last.resolve_label

        @breadcrumb_icon ||= chain.first.icon
        chain.each do |item|
          label = item.resolve_label
          url = item.safe_resolve_url(self)
          add_breadcrumb(label, url) if url.present?
        end
      end
    end
  end
end
