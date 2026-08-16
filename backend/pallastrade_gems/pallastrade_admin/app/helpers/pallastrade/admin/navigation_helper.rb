module PallasTrade
  module Admin
    module NavigationHelper
      # Creates a navigation item with optional icon
      # @param [String, SafeBuffer] label The text or HTML to use as the link content
      # @param [String] url The URL for the link
      # @param [String, nil] icon Optional icon name to prepend to the label
      # @param [Boolean, nil] active Whether the link should be marked as active
      # @return [SafeBuffer] The navigation item HTML
      def nav_item(label = nil, url, icon: nil, active: nil, data: {}, **options)
        content_tag :li, class: 'nav-item', role: 'presentation' do
          if block_given?
            active_link_to url, class: 'nav-link', active: active, data: data, **options do
              yield
            end
          else
            label = icon(icon) + label if icon.present? && label.present?
            active_link_to label, url, class: 'nav-link', active: active, data: data, **options
          end
        end
      end

      # the per_page_dropdown is used on index pages like orders, products, promotions etc.
      # this method generates the select_tag
      # @return [String]
      def per_page_dropdown
        per_page_default = if @products
                             PallasTrade::Admin::RuntimeConfig.admin_products_per_page
                           elsif @orders
                             PallasTrade::Admin::RuntimeConfig.admin_orders_per_page
                           else
                             PallasTrade::Admin::RuntimeConfig.admin_records_per_page
                           end

        per_page_options = [
          per_page_default,
          per_page_default * 2,
          per_page_default * 4,
          per_page_default * 8
        ]

        selected_option = (params[:per_page].try(:to_i) || per_page_default).to_i
        selected_option_label = selected_option.to_s + icon('chevron-down', class: 'ml-1 mr-0 arrow')

        dropdown(id: 'per-page-dropdown', portal: false) do
          dropdown_toggle(class: 'btn-light btn-sm') do
            raw(selected_option_label)
          end +
          dropdown_menu(direction: 'top-left') do
            per_page_options.map do |option|
              link_to option, per_page_dropdown_params(option), class: "dropdown-item #{'active' if option.to_i == selected_option}"
            end.join.html_safe
          end
        end
      end

      # helper method to create proper url to apply per page ing

      # @param per_page [Integer] the number of items per page
      # @return [Hash] the params to apply per page
      def per_page_dropdown_params(per_page)
        # Keep only safe query params that should survive pagination changes
        safe_params = request.query_parameters.slice(:q)
        safe_params.merge(per_page: per_page, page: nil)
      end

      # render a button link to edit a resource
      # if the current user doesn't have permission to update the resource, the button will not be rendered
      # @param resource [PallasTrade::Product, PallasTrade::User, PallasTrade::Order] the resource to edit
      # @param options [Hash] the options for the link
      # @option options [String] :url the url to edit the resource (optional)
      # @return [String] the link to edit the resource
      def link_to_edit(resource, options = {})
        url = options[:url] || edit_object_url(resource)
        options[:data] ||= {}
        options[:data][:action] ||= 'edit'
        options[:class] ||= 'btn btn-light btn-sm'
        link_to_with_icon('pencil', PallasTrade.t(:edit), url, options) if can?(:update, resource)
      end

      # render a button to delete a resource with a confirmation modal
      # if the current user doesn't have permission to destroy the resource, the button will not be rendered
      # @param resource [PallasTrade::Product, PallasTrade::User, PallasTrade::Order] the resource to delete
      # @param options [Hash] the options for the link
      # @option options [String] :url the url to delete the resource (optional)
      # @return [String] the link to delete the resource
      def link_to_delete(resource, options = {})
        url = options[:url] || object_url(resource)
        name = options[:name] || PallasTrade.t('actions.destroy')
        options[:class] ||= 'btn btn-danger btn-sm'
        options[:data] ||= { turbo_confirm: PallasTrade.t(:are_you_sure), turbo_method: :delete }

        return unless can?(:destroy, resource)

        if options[:no_text]
          link_to_with_icon 'trash', name, url, options
        elsif options[:icon]
          link_to_with_icon options[:icon], name, url, options
        else
          link_to name, url, options
        end
      end

      # renders a link with an icon
      # @param icon_name [String] the name of the icon, eg: 'pencil', see: https://tabler.io/icons
      # @param text [String] the text of the link
      # @param url [String] the url of the link
      # @param options [Hash] the options for the link
      # @return [String] the link with the icon
      def link_to_with_icon(icon_name, text, url, options = {})
        no_text = options[:no_text]
        tooltip_text = options[:title] || (no_text ? text : nil)
        options.delete(:no_text)
        options.delete(:title) if tooltip_text

        if tooltip_text
          options[:data] ||= {}
          options[:data][:controller] = 'tooltip'
        end

        label = no_text ? '' : content_tag(:span, text)

        if icon_name
          icon = icon(icon_name, class: "icon icon-#{icon_name} #{text.blank? || no_text ? 'mr-0' : ''}")
          text = "#{icon} #{label}"
        end

        link_content = text.html_safe
        link_content += tooltip(tooltip_text) if tooltip_text

        link_to(link_content, url, options)
      end

      def link_to_export_modal
        return unless can?(:create, PallasTrade::Export)

        button_tag(type: 'button', class: 'btn btn-light', data: { action: 'click->export-dialog#open' }) do
          icon('table-export', class: 'mr-0 mr-lg-2') +
          content_tag(:span, PallasTrade.t(:export), class: 'hidden lg:inline')
        end
      end

      # renders an active link with an icon, using the active_link_to method from https://github.com/comfy/active_link_to gem
      # @param icon_name [String] the name of the icon, eg: 'pencil', see: https://tabler.io/icons
      # @param text [String] the text of the link
      # @param url [String] the url of the link
      # @param options [Hash] the options for the link
      # @return [String] the active link with the icon
      def active_link_to_with_icon(icon_name, text, url, options = {})
        no_text = options[:no_text]
        tooltip_text = options[:title] || (no_text ? text : nil)
        options.delete(:no_text)
        options.delete(:title) if tooltip_text

        if tooltip_text
          options[:data] ||= {}
          options[:data][:controller] = 'tooltip'
        end

        label = no_text ? '' : content_tag(:span, text)

        if icon_name
          icon = icon(icon_name, class: "icon icon-#{icon_name}")
          text = "#{icon} #{label}"
        end

        link_content = text.html_safe
        link_content += tooltip(tooltip_text) if tooltip_text

        active_link_to(link_content, url, options)
      end

      # renders a button with an icon (optional)
      # Override: Add disable_with option to prevent multiple request on consecutive clicks
      # @param text [String] the text of the button
      # @param icon_name [String] the name of the icon, eg: 'pencil', see: https://tabler.io/icons
      # @param button_type [String] the type of the button, eg: 'submit', 'button'
      # @param options [Hash] the options for the button
      # @return [String] the button with the icon
      def button(text, icon_name = nil, button_type = 'submit', options = {})
        if icon_name
          text = "#{icon(icon_name, class: "icon icon-#{icon_name}")} #{text}"
        end

        css_classes = options[:class] || 'btn-primary'

        button_tag(
          text.html_safe,
          options.merge(
            type: button_type,
            class: "btn #{css_classes}",
            'data-turbo-submits-with' => content_tag(:span, '', class: 'inline-block w-4 h-4 border-2 border-current border-r-transparent rounded-full animate-spin', role: 'status')
          )
        )
      end

      def button_link_to(text, url, html_options = {})
        PallasTrade::Deprecation.warn("button_link_to is deprecated. Use standard link_to instead.")

        if html_options[:method] &&
            !html_options[:method].to_s.casecmp('get').zero? &&
            !html_options[:remote]

          html_options[:class] = html_options[:class] ? "btn #{html_options[:class]}" : 'btn btn-primary'

          form_tag(url, method: html_options.delete(:method)) do
            button(text, html_options.delete(:icon), nil, html_options)
          end
        else
          html_options[:class] = html_options[:class] ? "btn #{html_options[:class]}" : 'btn btn-light'

          if html_options[:icon]
            icon = icon(html_options[:icon], class: "icon icon-#{html_options[:icon]}")
            text = "#{icon} #{text}"
          end

          link_to(text.html_safe, url, html_options.except(:icon))
        end
      end

      # renders a badge (active/inactive)
      # @param condition [Boolean] the condition to check
      # @param options [Hash] the options for the badge
      # @return [String] the badge with the icon
      def active_badge(condition, options = {})
        label = options[:label]
        label ||= condition ? PallasTrade.t(:say_yes).to_s : PallasTrade.t(:say_no).to_s
        label = icon('check') + label if condition

        css_class = condition ? 'badge-active' : 'badge-inactive'

        content_tag(:span, class: "badge  #{css_class}") do
          label
        end
      end

      # renders a back button to the previous page
      # @param default_url [String] the default url to go back to
      # @param object [PallasTrade::Product, PallasTrade::User, PallasTrade::Order] the object list to go back to
      # @param label [String] the label of the back button (optional)
      # @return [String] the back button
      def page_header_back_button(default_url, object = nil, label = nil)
        url = default_url

        if object.present?
          session_key = "#{object.class.to_s.demodulize.pluralize.downcase}_return_to".to_sym
          url = session[session_key] if session[session_key].present?
        end

        link_to url, class: 'flex items-center no-underline' do
          content_tag(:span, icon('chevron-left', class: 'mr-0'), class: 'btn hover:bg-gray-100 shadow-none px-2 flex items-center shadow-none') +
            content_tag(:span, label, class: 'font-size-base text-black')
        end
      end

      # renders an external link with an icon (eg. pallastrade documentation website)
      # @param label [String] the label of the link
      # @param url [String] the url of the link
      # @param opts [Hash] the options for the link
      # @return [String] the external link with the icon
      def external_link_to(label, url, opts = {}, &block)
        opts[:target] ||= :blank
        opts[:rel] ||= :nofollow
        opts[:class] ||= "inline-flex items-center text-blue-500 no-underline hover:text-blue-600 hover:bg-blue-50 p-1 rounded"

        if block_given?
          link_to url, opts, &block
        else
          link_to url, opts do
            (label + icon('external-link', class: 'ml-1 mr-0 small opacity-50')).html_safe
          end
        end
      end

      # renders a link to preview a resource on the storefront using the pallastrade_storefront_resource_url helper
      # @param resource [PallasTrade::Product] the resource to preview
      # @param options [Hash] the options for the link
      # @return [String] the link to preview the resource
      def external_page_preview_link(resource, options = {})
        resource_name = options[:name] || resource.class.name.demodulize

        url = if resource.instance_of?(PallasTrade::Product)
                pallastrade_storefront_resource_url(resource, preview_id: resource.id)
              else
                pallastrade_storefront_resource_url(resource)
              end

        link_to_with_icon(
          'eye',
          PallasTrade.t('admin.utilities.preview', name: resource_name),
          url,
          class: 'text-left dropdown-item', id: "adminPreview#{resource_name}", target: :blank, data: { turbo: false }
        )
      end

      # renders a help bubble with an icon
      # @param text [String] the text of the help bubble
      # @param placement [String] the placement of the help bubble
      # @param css [String] the css class of the help bubble
      # @return [String] the help bubble with the icon
      def help_bubble(text = '', placement = 'top', css: nil)
        css ||= 'text-gray-500 cursor-default opacity-75'
        content_tag :span, data: { controller: 'tooltip', tooltip_placement_value: placement } do
          icon('info-square-rounded', class: css) + tooltip(text)
        end
      end

      # PALLAS-CUSTOM: P6 起主区/设置区统一（不再区分 settings_area），
      # 图标一律取导航项图标或控制器声明的 @breadcrumb_icon。
      def render_breadcrumb_icon
        icon(@breadcrumb_icon) if @breadcrumb_icon
      end

      # Renders the navigation for the given context
      # @param context [Symbol] the navigation context (:sidebar, :settings, etc.)
      # @param options [Hash] additional options for rendering
      # @return [String] the rendered navigation HTML
      def render_navigation(context = :sidebar, **options)
        items = navigation_items(context)
        return '' if items.empty?

        render_navigation_items(items, context)
      end

      # Get navigation items for the given context
      # @param context [Symbol] the navigation context
      # @return [Array<PallasTrade::Admin::Navigation::Item>] the visible navigation items
      def navigation_items(context = :sidebar)
        nav = PallasTrade.admin.navigation.send(context)
        # PALLAS-CUSTOM: 菜单权限过滤（P3 权限体系重构）
        # DB 驱动角色（menu_permissions 已配置）：菜单树完全由菜单权限决定（跳过代码 if:）；
        # 否则按代码 if: 条件（向后兼容）。
        items = menu_driven? ? (nav&.root_items || []) : (nav&.visible_items(self) || [])
        items.select { |item| menu_granted?(item) }
      end

      # PALLAS-CUSTOM: 当前角色是否由 DB 菜单权限驱动（P3 权限体系重构）
      def menu_driven?
        !menu_permissions_for_ability.nil?
      end

      # PALLAS-CUSTOM: 当前 Ability 的菜单权限（P3 权限体系重构）
      def menu_permissions_for_ability
        ability = respond_to?(:current_ability) ? current_ability : nil
        ability.respond_to?(:menu_permissions) ? ability.menu_permissions : nil
      end

      # PALLAS-CUSTOM: 角色菜单权限过滤（P3 权限体系重构）
      # 当当前用户的 Ability 配置了 menu_permissions（DB 驱动角色）时：
      #   - :all        → 全部可见
      #   - Array       → 仅授权的项（顶级项因其任一子项被授权而保留）
      # 未配置菜单权限（menu_permissions 为 nil）→ 不过滤（默认全量，向后兼容）。
      # @param item [PallasTrade::Admin::Navigation::Item]
      # @return [Boolean]
      def menu_granted?(item)
        perms = menu_permissions_for_ability
        return true if perms.nil? || perms == :all

        perms.include?(item.key.to_s) || item.children.any? { |child| perms.include?(child.key.to_s) }
      end

      # Renders navigation items as an unordered list
      # @param items [Array<PallasTrade::Admin::Navigation::Item>] navigation items to render
      # @param context [Symbol] the navigation context
      # @return [SafeBuffer] the rendered HTML
      def render_navigation_items(items, context)
        return ''.html_safe if items.empty?

        content_tag :ul, class: 'nav flex-col' do
          safe_join(items.map { |item| render_navigation_item(item, context) })
        end
      end

      # Renders a single navigation item
      # @param item [PallasTrade::Admin::Navigation::Item] the navigation item
      # @param context [Symbol] the navigation context
      # @return [SafeBuffer] the rendered HTML
      def render_navigation_item(item, context)
        return render_nav_section_header(item) if item.section?

        item_url = item.resolve_url(self)
        item_label = item.resolve_label
        badge_value = item.badge_value(self)
        is_active = item.active?(request.path, self)
        has_children = item.children.present?
        tooltip_text = item.tooltip

        # PALLAS-CUSTOM: 顶级落地（P6 导航架构重构）
        # 带子菜单的一级项点击时落到 landing 子项（缺省 = 第一个可见子项），
        # 与 Email 菜单行为一致（Orders → All Orders、Developers → API Keys）。
        if has_children
          landing_item = item.landing_item(self)
          item_url = landing_item.resolve_url(self) if landing_item&.resolve_url(self)
        end

        # Build data attributes
        data_attrs = item.data_attributes.dup
        data_attrs[:controller] = 'tooltip' if tooltip_text.present?

        # Build HTML options
        html_options = {}
        html_options[:target] = item.target if item.target.present?
        html_options[:id] = "nav-link-#{item.key}" if item.key.present?

        # Build complete label with badge and tooltip
        complete_label = build_nav_label(item_label, badge_value, item.badge_class, tooltip_text)

        if has_children
          render_nav_item_with_children(item, complete_label, item_url, item_label, is_active, data_attrs, html_options, context)
        else
          nav_item(complete_label, item_url, icon: item.icon, active: is_active, data: data_attrs, **html_options)
        end
      end

      # Renders page tab navigation for the given context
      # @param context [Symbol] the navigation context (:tax_tabs, :shipping_tabs, etc.)
      # @param options [Hash] additional options for rendering
      # @return [String] the rendered tab navigation HTML wrapped in content_for(:page_tabs)
      def render_tab_navigation(context, **options)
        items = navigation_items(context)
        return '' if items.empty?

        content_for :page_tabs do
          items.map do |item|
            item_url = item.resolve_url(self)
            item_label = item.resolve_label
            is_active = item.active?(request.path, self)

            nav_item(item_label, item_url, active: is_active)
          end.join.html_safe
        end
      end

      private

      # Builds navigation label with optional badge and tooltip
      # @return [SafeBuffer] the label HTML
      def build_nav_label(label, badge_value, badge_class, tooltip_text)
        result = label.to_s
        if badge_value.present?
          css_class = badge_class.presence || 'badge-light'
          result += content_tag(:span, badge_value, class: "badge ms-auto #{css_class}")
        end
        if tooltip_text.present?
          result += tooltip(tooltip_text)
        end
        result.html_safe
      end

      # Renders a section header
      # @return [SafeBuffer] the section header HTML
      def render_nav_section_header(item)
        content_tag :li, class: 'nav-item nav-section-header mt-4 border-t pt-4 pl-2' do
          content_tag :span, item.section_label, class: 'text-gray-600 uppercase font-light text-sm'
        end
      end

      # Renders a nav item that has children (with submenu)
      # @return [SafeBuffer] the nav item with submenu HTML
      def render_nav_item_with_children(item, complete_label, item_url, item_label, is_active, data_attrs, html_options, context)
        # PALLAS-CUSTOM: 菜单权限过滤（P3 权限体系重构）
        # DB 驱动角色按菜单权限过滤子项；否则按代码 if: 条件。
        visible_children = item.children.select do |child|
          menu_driven? ? menu_granted?(child) : (child.visible?(self) && menu_granted?(child))
        end
        return '' if visible_children.empty? && !menu_granted?(item)

        # Main nav item
        main_item = nav_item(complete_label, item_url, icon: item.icon, active: is_active, data: data_attrs, **html_options)

        # Submenu for expanded sidebar (only shown when active)
        submenu = content_tag :ul, class: "nav-submenu#{' hidden' unless is_active}", id: "nav-submenu-#{item.key}" do
          safe_join(visible_children.map { |child| render_navigation_item(child, context) })
        end

        # Dropdown submenu for collapsed sidebar (shown on hover)
        dropdown = content_tag :ul, class: 'nav-submenu-dropdown hidden dropdown-container', id: "nav-submenu-dropdown-#{item.key}" do
          # Parent item as first dropdown item
          parent_link = nav_item(item_label, item_url, icon: nil)
          children_items = safe_join(visible_children.map { |child| render_navigation_item(child, context) })
          parent_link + children_items
        end

        main_item + submenu + dropdown
      end
    end
  end
end
