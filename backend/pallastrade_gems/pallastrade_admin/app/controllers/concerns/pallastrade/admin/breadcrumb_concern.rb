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
        class_attribute :skip_breadcrumb_derivation, default: false
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

      # P5 起：设置区也用导航配置自动推导面包屑（Settings > 页面），
      # 不再需要每个设置控制器手写 `add_breadcrumb`。
      # 特殊控制器（如 stores 的 section 级自定义 crumb）可声明
      # `self.skip_breadcrumb_derivation = true` 保留手写逻辑。
      def derive_breadcrumbs_from_navigation
        return unless respond_to?(:add_breadcrumb, true)
        return if self.class.skip_breadcrumb_derivation

        if settings_controller?
          derive_settings_breadcrumb
        else
          derive_sidebar_breadcrumb
        end
      end

      # 主区（sidebar）：请求路径 → 导航项（最深 URL 匹配）→ 图标 + 父 + 子 面包屑。
      # 同时记录 @navigation_page_title（最深匹配项 label）供 page_title fallback。
      def derive_sidebar_breadcrumb
        chain = PallasTrade.admin.navigation.sidebar&.find_breadcrumb_chain(request.path, self)
        return if chain.blank?

        @navigation_page_title ||= chain.last.resolve_label
        @breadcrumb_icon ||= chain.first.icon
        chain.each do |item|
          label = item.resolve_label
          url = item.safe_resolve_url(self)
          add_breadcrumb(label, url) if url.present?
        end
      end

      # 设置区（settings）：settings nav 是 section 级，先按 active 条件命中 section 项，
      # 再经 SETTINGS_TAB_MAP 找到页面级 tab 项取 label（Settings 前缀由 _breadcrumbs
      # partial 的 settings_area? 分支自动加）。
      def derive_settings_breadcrumb
        nav = PallasTrade.admin.navigation.settings
        return unless nav

        item = nav.items.values.find { |i| i.active?(request.path, self) }
        return unless item

        page = settings_page_item(item) || item
        label = page.resolve_label
        url = page.safe_resolve_url(self) || item.safe_resolve_url(self)
        add_breadcrumb(label, url) if label.present? && url.present?
      end

      # 若 section 项关联页面级 tab 注册表，返回匹配当前路径的 tab 项（页面级 label）。
      def settings_page_item(item)
        tab_context = PallasTrade::Admin::Navigation::SETTINGS_TAB_MAP[item.key]
        return nil unless tab_context

        tab_nav = PallasTrade.admin.navigation.public_send(tab_context)
        tab_nav&.items&.values&.find { |tab| tab.active?(request.path, self) || tab.match_path?(request.path, self) }
      end
    end
  end
end
