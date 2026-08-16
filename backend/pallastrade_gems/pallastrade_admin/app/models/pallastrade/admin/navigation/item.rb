module PallasTrade
  module Admin
    class Navigation
      class Item
        attr_accessor :key, :label, :url, :icon, :position, :parent_key,
                      :condition, :badge, :badge_class, :tooltip, :target, :data_attributes, :children, :section_label, :active_condition,
                      :landing, :tabs

        def initialize(key, **options)
          @key = key.to_sym
          @label = options[:label]
          @url = options[:url]
          @icon = options[:icon]
          @position = options[:position] || 999
          @parent_key = options[:parent]
          @active_condition = options[:active]
          @condition = options.key?(:if) ? options[:if] : options[:condition]
          @badge = options[:badge]
          @badge_class = options[:badge_class]
          @tooltip = options[:tooltip]
          @target = options[:target]
          @data_attributes = options[:data_attributes] || {}
          @section_label = options[:section_label]
          @landing = options[:landing]&.to_sym
          @tabs = options[:tabs]&.to_sym
          @children = []
        end

        # PALLAS-CUSTOM: 顶级落地子项（P6 导航架构重构）
        # 点击带子菜单的一级项时，落到该子项（默认 = 第一个可见子项）。
        # @return [Item, nil] the landing child item, or nil when no children
        def landing_item(context = nil)
          return nil if children.empty?

          if landing
            target = children.find { |child| child.key == landing }
            return target if target
          end

          children.find { |child| child.visible?(context) } || children.first
        end

        # Check if this item should be visible for the given user/context
        # @param user_or_context [Object] Either a user object or a view context
        def visible?(user_or_context = nil)
          return true if condition.nil?

          if condition.respond_to?(:call)
            # If we have a view context with instance_exec, use it to evaluate the condition
            # This allows access to can? and other helper methods
            if user_or_context.respond_to?(:instance_exec)
              user_or_context.instance_exec(&condition)
            else
              # Otherwise, call with the user object
              condition.call(user_or_context)
            end
          else
            condition
          end
        end

        # Check if this item is active based on current path
        # @param current_path [String] The current request path
        # @param context [Object] View context with access to route helpers
        def active?(current_path, context = nil)
          # Use custom active condition if provided (most flexible)
          if active_condition.respond_to?(:call)
            if context&.respond_to?(:instance_exec)
              return context.instance_exec(&active_condition)
            else
              return active_condition.call
            end
          end

          # Match exact path
          item_url = resolve_url(context)
          return true if item_url && current_path == item_url

          # Check if any child item is active
          return true if children.any? { |child| child.active?(current_path, context) }

          # Default: match if path starts with url (handled by active_link_to)
          if item_url
            current_path.start_with?(item_url)
          else
            false
          end
        end

        # Resolve URL (handles symbols, procs, and strings)
        # @param context [Object] View context with access to route helpers
        def resolve_url(context = nil)
          case url
          when Symbol
            # Try to call the route helper on the context (which has pallastrade routes)
            if context&.respond_to?(url)
              context.send(url)
            elsif context&.respond_to?(:pallastrade)
              context.PallasTrade.send(url) rescue url.to_s
            else
              url.to_s
            end
          when Proc
            # Evaluate proc in the context where route helpers are available
            if context&.respond_to?(:instance_exec)
              context.instance_exec(&url)
            else
              url.call
            end
          else
            url
          end
        end

        # Safe URL resolution that never raises (used for path indexing).
        # @return [String, nil] the resolved URL or nil on any error
        def safe_resolve_url(context = nil)
          resolve_url(context)
        rescue StandardError
          nil
        end

        # PALLAS-CUSTOM: 面包屑自动推导（P3 导航架构重构）
        # Whether this item's URL matches the given request path (exact match
        # or as a path prefix — e.g. /admin/orders matches /admin/orders/123).
        # Shallow URLs (a single admin segment like `/admin`) only exact-match,
        # so the Dashboard item never hijacks unrelated `/admin/*` pages
        # (settings pages, AI module, imports wizard, etc.).
        # P6 起 query 感知：带 query 的项（如 Orders to Fulfill 的
        # q[shipment_state_not_in]=...）仅在 path+query 都相等时命中，绝不落入
        # path-only 兜底（否则会与同路径的 All Orders 混淆）。
        # @param path [String] the current request path (no query string)
        # @param context [Object] controller/view context for URL resolution
        # @param query [String, nil] raw query string (no leading ?)
        # @return [Boolean]
        def match_path?(path, context = nil, query: nil)
          item_url = safe_resolve_url(context)
          return false if item_url.blank?

          item_path, item_query = item_url.to_s.split('?', 2)

          return path == item_path if shallow_url?(item_path)

          # 带 query 的项：path + query 均相等才命中（Orders to Fulfill 专用）
          if item_query.present?
            return path == item_path && query == item_query
          end

          path == item_path || path.start_with?("#{item_path}/")
        end

        # PALLAS-CUSTOM: query 命中判断（P6 导航架构重构）
        # 该 item 的 URL 是否携带与给定 query 完全一致的 query 串。
        # 用于 find_breadcrumb_chain 中同深度项的排序（query 命中优先）。
        # @param query [String] raw query string (no leading ?)
        # @param context [Object] controller/view context for URL resolution
        # @return [Boolean]
        def query_match?(query, context = nil)
          return false if query.blank?

          item_url = safe_resolve_url(context).to_s
          _item_path, item_query = item_url.split('?', 2)
          item_query.present? && item_query == query
        end

        # Resolve label (handles i18n keys)
        # PALLAS-CUSTOM: 普通字符串 label 原样返回（不做 humanize），
        # 只有 i18n key（含点）才翻译——修复自定义菜单项/中文 label 被 humanize 的问题。
        def resolve_label
          case label
          when String
            label.include?('.') ? PallasTrade.t(label, default: label.humanize) : label
          when Symbol
            PallasTrade.t(label, default: label.to_s.humanize)
          else
            label
          end
        end

        # Compute badge value
        # @param view_context [Object] View context with access to helper methods
        def badge_value(view_context = nil)
          return nil unless badge

          if badge.respond_to?(:call)
            # Evaluate badge in view context if available (for access to helpers)
            if view_context&.respond_to?(:instance_exec)
              view_context.instance_exec(&badge)
            else
              badge.call
            end
          else
            badge
          end
        end

        # Check if this is a section header
        def section?
          section_label.present?
        end

        # Add a child item
        def add_child(item)
          children << item
          item.parent_key = key
          sort_children!
        end

        # Remove a child item
        def remove_child(key)
          children.reject! { |child| child.key == key }
        end

        # Sort children by position
        def sort_children!
          children.sort_by! { |child| [child.position, child.key.to_s] }
        end

        # Deep clone for modifications
        def deep_clone
          cloned = self.class.new(key, **to_h)
          cloned.children = children.map(&:deep_clone)
          cloned
        end

        # Convert to hash
        def to_h
          {
            label: label,
            url: url,
            icon: icon,
            position: position,
            parent: parent_key,
            active: active_condition,
            condition: condition,
            badge: badge,
            badge_class: badge_class,
            tooltip: tooltip,
            target: target,
            data_attributes: data_attributes,
            section_label: section_label,
            landing: landing,
            tabs: tabs
          }
        end

        def inspect
          "#<PallasTrade::Admin::Navigation::Item key=#{key} label=#{label} children=#{children.size}>"
        end

        private

        # A "shallow" URL has at most one path segment (e.g. `/admin`).
        def shallow_url?(url)
          url.split('/').reject(&:empty?).length <= 1
        end
      end
    end
  end
end
