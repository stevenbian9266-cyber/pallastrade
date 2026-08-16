module PallasTrade
  module Admin
    # PALLAS-CUSTOM: 面包屑自动推导（P3 导航架构重构）
    #
    # 页面不再需要手写 breadcrumb concern / add_breadcrumb：
    # 请求路径 → 导航配置 → 自动 图标 + 一级 + 二级(+tab) 面包屑。
    # P6 起主区/设置区统一走同一棵 sidebar 导航树推导。
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

      # P6 起：主区/设置区统一从 sidebar 导航树推导。
      # 特殊控制器（如 stores 的 section 级自定义 crumb）可声明
      # `self.skip_breadcrumb_derivation = true` 保留手写逻辑。
      def derive_breadcrumbs_from_navigation
        return unless respond_to?(:add_breadcrumb, true)
        return if self.class.skip_breadcrumb_derivation

        derive_sidebar_breadcrumb
      end

      # 统一（sidebar）：请求路径 → 最深导航项（URL 命中，含 query 感知，
      # 支持 Orders to Fulfill 这类同路径异 query 子项）→ 一级 + 二级(+tab)
      # 面包屑。同时记录 @navigation_page_title（最深项 label）供 page_title
      # fallback。
      def derive_sidebar_breadcrumb
        chain = PallasTrade.admin.navigation.sidebar&.find_breadcrumb_nodes(request.path, self, query: request.query_string)
        return if chain.blank?

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
