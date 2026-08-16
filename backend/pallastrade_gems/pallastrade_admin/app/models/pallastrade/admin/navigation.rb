module PallasTrade
  module Admin
    class Navigation
      # PALLAS-CUSTOM: 设置区 section/tabs 统一注册表（P4 导航架构重构）
      # 每个 section 声明 banner 标题、tabs 上下文与可选附加内容，由
      # `shared/_section_nav` 统一渲染（替代 _developers_nav/_team_nav/
      # _audit_nav/_returns_and_refunds_nav 4 个手写 banner partial）。
      # P6 起侧边栏已统一为单一树，本注册表仅保留页面级 section banner。
      SETTINGS_SECTIONS = {
        developers: { title: :developers, tabs: :developers_tabs },
        team: {
          title: :users,
          tabs: :team_tabs,
          page_actions: 'pallastrade/admin/shared/team_nav_actions',
          nav_partials: :team_nav_partials
        },
        audit: { title: 'admin.audit_log', tabs: :audit_tabs },
        returns: {
          title: -> { "#{PallasTrade.t(:returns)} & #{PallasTrade.t(:refunds)}" },
          tabs: :returns_tabs,
          nav_partials: :returns_and_refunds_nav_partials
        }
      }.freeze

      attr_reader :items, :context

      def initialize(context)
        @context = context
        @items = {}
      end

      # Add a navigation item
      def add(key, **options, &block)
        key = key.to_sym
        item = Item.new(key, **options)

        @items[key] = item

        # If block provided, it's for children
        if block_given?
          builder = Builder.new(self, item)
          # Support both block styles: |nav| nav.add or just add
          if block.arity > 0
            # Block expects parameter: do |nav| nav.add ... end
            block.call(builder)
          else
            # Block uses implicit self: do add ... end
            builder.instance_eval(&block)
          end
        end

        sort_items!
        item
      end

      # Remove a navigation item
      def remove(key)
        key = key.to_sym
        removed = @items.delete(key)

        # Also remove from any parent's children
        @items.each_value do |item|
          item.remove_child(key)
        end

        removed
      end

      # Update an existing navigation item
      def update(key, **options)
        key = key.to_sym
        item = @items[key]

        return nil unless item

        options.each do |attr, value|
          item.send("#{attr}=", value) if item.respond_to?("#{attr}=")
        end

        sort_items!
        item
      end

      # Find a navigation item
      def find(key)
        @items[key.to_sym]
      end

      # Check if item exists
      def exists?(key)
        @items.key?(key.to_sym)
      end

      # Insert item before another item
      def insert_before(target_key, new_key, **options)
        target = find(target_key)
        return nil unless target

        new_position = target.position - 1
        add(new_key, **options.merge(position: new_position))
      end

      # Insert item after another item
      def insert_after(target_key, new_key, **options)
        target = find(target_key)
        return nil unless target

        new_position = target.position + 1
        add(new_key, **options.merge(position: new_position))
      end

      # Move item to a new position
      def move(key, position: nil, before: nil, after: nil)
        item = find(key)
        return nil unless item

        if before
          target = find(before)
          item.position = target.position - 1 if target
        elsif after
          target = find(after)
          item.position = target.position + 1 if target
        elsif position == :first
          item.position = -999
        elsif position == :last
          item.position = 999
        elsif position.is_a?(Integer)
          item.position = position
        end

        sort_items!
        item
      end

      # Replace an item
      def replace(key, **options, &block)
        remove(key)
        add(key, **options, &block)
      end

      # Get all root items (items without a parent)
      def root_items
        @items.values.select { |item| item.parent_key.nil? }.sort_by { |item| [item.position, item.key.to_s] }
      end

      # Get all items that are visible to the user
      def visible_items(user = nil, parent_key = nil)
        items_to_filter = if parent_key
                            find(parent_key)&.children || []
                          else
                            root_items
                          end

        items_to_filter.select { |item| item.visible?(user) }
      end

      # Build tree structure
      def build_tree
        # First, clear all children
        @items.each_value { |item| item.children.clear }

        # Then rebuild the tree
        @items.each_value do |item|
          if item.parent_key && (parent = @items[item.parent_key])
            parent.add_child(item)
          end
        end

        root_items
      end

      # Clear all items
      def clear
        @items.clear
      end

      # Get all registered paths (for settings_area? detection)
      def registered_paths(context = nil)
        @items.values.map { |item| item.resolve_url(context) }.compact
      end

      # PALLAS-CUSTOM: 面包屑自动推导（P3 导航架构重构）
      # Find the navigation item (and its ancestor chain) that best matches a
      # request path — the deepest matching item wins, so /admin/emails
      # resolves to email_settings (child) → chain [emails, email_settings]
      # while /admin/orders resolves to orders → chain [orders].
      # P6 起支持 query 感知：query 命中的子项（如 Orders to Fulfill 的
      # q[shipment_state_not_in]）优先于同路径兄弟项。
      # @param path [String] the current request path (no query string)
      # @param context [Object] controller/view context for URL resolution
      # @param query [String, nil] raw query string (no leading ?)
      # @return [Array<Item>, nil] ancestor chain root→matched, or nil
      def find_breadcrumb_chain(path, context = nil, query: nil)
        matched = @items.values.select { |item| item.match_path?(path, context, query: query) }
        return nil if matched.empty?

        best = matched.max_by do |item|
          [depth_of(item), query && item.query_match?(query, context) ? 1 : 0, item.safe_resolve_url(context).to_s.length]
        end

        chain = []
        current = best
        while current
          chain.unshift(current)
          current = current.parent_key ? @items[current.parent_key] : nil
        end
        chain
      end

      # PALLAS-CUSTOM: 面包屑自动推导（P6 导航架构重构）
      # 在 find_breadcrumb_chain 基础上追加 tab 节点：若链上任一项（或最深项
      # 的直接子项）声明了 `tabs:` 上下文，且该 tab 注册表中有项命中当前路径，
      # 则把 tab 项追加为末级 crumb（Products > Stock > Stock Movements）。
      # 已存在于链中的项会被去重，避免 Tax > Tax Rates > Tax Rates 之类重复。
      # 当 URL 匹配为空或不够深时，用 active 条件补全（如 /admin/stock_movements
      # 的 URL 不在 Products/Stock 之下，但 stock 的 active? 命中三个库存控制器）。
      # @param path [String] the current request path (no query string)
      # @param context [Object] controller/view context for URL resolution
      # @param query [String, nil] raw query string (no leading ?)
      # @return [Array<Item>, nil] ancestor chain root→matched(+tab), or nil
      def find_breadcrumb_nodes(path, context = nil, query: nil)
        chain = find_breadcrumb_chain(path, context, query: query)

        active_chain = find_active_breadcrumb_chain(path, context)
        if active_chain && (chain.nil? || active_chain.size > chain.size)
          chain = active_chain
        end

        return nil unless chain

        deepest = chain.last
        tab_owner = chain.reverse.find { |item| item.tabs }
        tab_owner ||= deepest&.children&.find { |child| child.tabs }

        if tab_owner
          tab_chain = self.class.tab_context(tab_owner.tabs)&.find_breadcrumb_chain(path, context, query: query)
          if tab_chain
            chain += [tab_owner] unless chain.include?(tab_owner)
            chain += tab_chain.reject { |tab| chain.any? { |c| c.key == tab.key } }
          end
        end

        chain
      end

      # PALLAS-CUSTOM: active 条件兜底（P6 导航架构重构）
      # 当 URL 匹配不到（如 /admin/stock_movements 与 Products/Stock 的 URL
      # 都不重叠），按 active? 条件找最深命中项并回溯祖先链。所有 active
      # lambda 均为 controller_name/action 白名单，安全。
      # @param path [String] the current request path (no query string)
      # @param context [Object] controller/view context for URL resolution
      # @return [Array<Item>, nil]
      def find_active_breadcrumb_chain(path, context = nil)
        active_items = @items.values.select do |item|
          item.safe_resolve_url(context).present? && item.active?(path, context)
        end
        return nil if active_items.empty?

        best = active_items.max_by { |item| depth_of(item) }

        chain = []
        current = best
        while current
          chain.unshift(current)
          current = current.parent_key ? @items[current.parent_key] : nil
        end
        chain
      end

      # PALLAS-CUSTOM: 顶级落地解析（P6 导航架构重构）
      # 返回一级项的落地子项（landing 指定的子项，缺省 = 第一个可见子项）。
      # @param item [Item] a top-level navigation item with children
      # @param context [Object] controller/view context for visibility checks
      # @return [Item, nil]
      def find_landing(item, context = nil)
        item&.landing_item(context)
      end

      # PALLAS-CUSTOM: 按名称解析 tab 上下文（P6 导航架构重构）
      # 例如 :stock_tabs → PallasTrade.admin.navigation.stock_tabs。
      # @param name [Symbol] registered tab context name
      # @return [Navigation, nil]
      def self.tab_context(name)
        return nil if name.nil?

        PallasTrade.admin.navigation.get_context(name)
      rescue NoMethodError, ArgumentError
        nil
      end

      # Add a section
      def section(key, label: nil, &block)
        # Create a section header item
        section_item = add(key, section_label: label || key.to_s.humanize, position: @items.size * 100)

        if block_given?
          builder = Builder.new(self, section_item)
          builder.instance_eval(&block)
        end

        section_item
      end

      # Deep clone the registry
      def deep_clone
        cloned = self.class.new(context)
        @items.each do |key, item|
          cloned.items[key] = item.deep_clone
        end
        cloned.build_tree
        cloned
      end

      private

      # Depth of an item in the tree (root = 0)
      def depth_of(item)
        depth = 0
        current = item
        while current&.parent_key && (parent = @items[current.parent_key])
          depth += 1
          current = parent
        end
        depth
      end

      def sort_items!
        # Sort items by position, then rebuild tree
        @items = @items.sort_by { |_key, item| [item.position, item.key.to_s] }.to_h
        build_tree
      end
    end
  end
end
