# Default Admin Navigation Configuration
# This file defines the default sidebar and settings navigation for PallasTrade Admin

Rails.application.config.after_initialize do
  # ===============================================
  # Sidebar Navigation
  # ===============================================
  sidebar_nav = PallasTrade.admin.navigation.sidebar

  # Getting Started (onboarding)
  sidebar_nav.add :getting_started,
          label: 'admin.getting_started',
          url: :admin_getting_started_path,
          icon: 'map',
          position: 5,
          if: -> { current_store && can?(:manage, current_store) && !current_store.setup_completed? },
          badge: -> { "#{current_store.setup_tasks_done}/#{current_store.setup_tasks_total}" },
          badge_class: 'badge-info',
          active: -> { controller_name == 'dashboard' && action_name == 'getting_started' }

  # Dashboard / Home
  sidebar_nav.add :home,
          label: :home,
          url: :admin_path,
          icon: 'home',
          position: 10,
          active: -> { controller_name == 'dashboard' && action_name == 'show' }

  # Orders with submenu — P6：顶级落地 = All Orders（landing），
  # 点击 Orders 落到全部订单页，子菜单第一个次级菜单默认高亮。
  sidebar_nav.add :orders,
          label: :orders,
          url: :admin_orders_path,
          icon: 'inbox',
          position: 20,
          landing: :all_orders,
          if: -> { can?(:manage, PallasTrade::Order) },
          badge: -> {
            # Evaluated in view context with access to helper methods
            ready_to_ship_orders_count if ready_to_ship_orders_count&.positive?
          } do |orders|
    # All Orders（次级菜单第一项，顶级落地）
    orders.add :all_orders,
              label: 'admin.orders.all_orders',
              url: :admin_orders_path,
              position: 5,
              active: -> { controller_name == 'orders' && params.dig(:q, :shipment_state_not_in).blank? }

    # Orders to Fulfill submenu
    orders.add :orders_to_fulfill,
              label: 'admin.orders.orders_to_fulfill',
              url: -> {
                query_state = {
                  id: 'root',
                  combinator: 'and',
                  filters: [
                    { id: 'f1', field: 'shipment_state', operator: 'not_in', value: [
                      { id: 'shipped', name: I18n.t('pallastrade.shipment_states.shipped', default: 'Shipped') },
                      { id: 'canceled', name: I18n.t('pallastrade.shipment_states.canceled', default: 'Canceled') }
                    ] }
                  ],
                  groups: []
                }.to_json
                PallasTrade.admin_orders_path(q: { shipment_state_not_in: ['shipped', 'canceled'] }, query_state: query_state)
              },
              position: 10,
              active: -> { controller_name == 'orders' && params.dig(:q, :shipment_state_not_in).present? },
              # 常显原则：菜单不因业务状态（count>0）隐藏；数量用 badge 表达
              badge: -> {
                ready_to_ship_orders_count if ready_to_ship_orders_count&.positive?
              }

    # Draft Orders
    orders.add :draft_orders,
              label: :draft_orders,
              url: :admin_checkouts_path,
              position: 20,
              active: -> { controller_name == 'checkouts' || (@order.present? && !@order.completed?) },
              if: -> { can?(:manage, :checkouts) }

    # PALLAS-CUSTOM: 支付组查看（PRD-20260823-checkout-多订单拆分与合并支付）
    orders.add :payment_groups,
              label: :payment_groups,
              url: :admin_payment_groups_path,
              position: 30,
              active: -> { controller_name == 'payment_groups' },
              if: -> { can?(:read, PallasTrade::PaymentGroup) }
  end

  # Returns with submenu — P6：顶级落地 = Customer Returns
  sidebar_nav.add :returns,
          label: :returns,
          url: :admin_customer_returns_path,
          icon: 'receipt-refund',
          position: 25,
          landing: :customer_returns,
          if: -> { can?(:manage, PallasTrade::CustomerReturn) || can?(:manage, PallasTrade::ReturnAuthorization) } do |returns|
    # Customer Returns（次级菜单第一项，顶级落地）
    returns.add :customer_returns,
                label: 'admin.returns.customer_returns',
                url: :admin_customer_returns_path,
                position: 5,
                active: -> { controller_name == 'customer_returns' }
    # Return Authorizations
    returns.add :return_authorizations,
                label: :return_authorizations,
                url: :admin_return_authorizations_path,
                position: 10,
                if: -> { can?(:manage, PallasTrade::ReturnAuthorization) }
  end

  # Products with submenu — P6：顶级落地 = Products List
  sidebar_nav.add :products,
          label: :products,
          url: :admin_products_path,
          icon: 'package',
          position: 30,
          landing: :products_list,
          if: -> { can?(:manage, PallasTrade::Product) } do |products|

    # Products List（次级菜单第一项，顶级落地）
    products.add :products_list,
                label: 'admin.products.products_list',
                url: :admin_products_path,
                position: 5,
                active: -> { controller_name == 'products' && action_name == 'index' }

    # Price Lists
    products.add :price_lists,
                label: :price_lists,
                url: :admin_price_lists_path,
                position: 10,
                active: -> { %w[price_lists price_rules].include?(controller_name) },
                if: -> { can?(:manage, PallasTrade::PriceList) }
    # Stock（页面级 tabs：Stock Items / Stock Movements / Stock Transfers）
    products.add :stock,
                label: :stock,
                url: :admin_stock_items_path,
                position: 20,
                tabs: :stock_tabs,
                active: -> { %w[stock_items stock_movements stock_transfers].include?(controller_name) },
                if: -> { can?(:manage, PallasTrade::StockItem) || can?(:manage, PallasTrade::StockMovement) || can?(:manage, PallasTrade::StockTransfer) }

    # Translations
    products.add :translations,
                label: :translations,
                url: :admin_product_translations_path,
                position: 25,
                active: -> { controller_name == 'product_translations' },
                # 常显原则：单语言店铺也显示，页面内做空态引导
                if: -> { can?(:manage, PallasTrade::Product) }

    # Taxonomies / Categories（P6 统一命名 Categories）
    products.add :taxonomies,
                label: 'admin.products.categories',
                url: :admin_taxonomies_path,
                position: 30,
                active: -> { %w[taxonomies taxons].include?(controller_name) },
                if: -> { can?(:manage, PallasTrade::Taxonomy) && can?(:manage, PallasTrade::Taxon) }

    # Options
    products.add :options,
                label: :options,
                url: :admin_option_types_path,
                position: 40,
                active: -> { %w[option_types option_values].include?(controller_name) },
                if: -> { can?(:manage, PallasTrade::OptionType) }

  end

  # Customers with submenu — P6：顶级落地 = Customers List
  sidebar_nav.add :customers,
          label: :customers,
          url: :admin_users_path,
          icon: 'users',
          position: 40,
          landing: :customers_list,
          if: -> { can?(:manage, PallasTrade.user_class) } do |customers|
    # Customers List（次级菜单第一项，顶级落地）
    customers.add :customers_list,
                  label: 'admin.customers.customers_list',
                  url: :admin_users_path,
                  position: 5,
                  active: -> { controller_name == 'users' && action_name == 'index' }
    # Customer Groups
    customers.add :customer_groups,
                  label: :customer_groups,
                  url: :admin_customer_groups_path,
                  position: 10,
                  active: -> { %w[customer_groups customer_group_users].include?(controller_name) },
                  if: -> { can?(:manage, PallasTrade::CustomerGroup) }

    # Newsletter Subscribers
    customers.add :newsletter_subscribers,
                  label: :newsletter_subscribers,
                  url: :admin_newsletter_subscribers_path,
                  position: 20
  end

  # Promotions with submenu — P6：顶级落地 = Promotions List
  sidebar_nav.add :promotions,
          label: :promotions,
          url: :admin_promotions_path,
          icon: 'discount',
          position: 50,
          landing: :promotions_list,
          if: -> { can?(:manage, PallasTrade::Promotion) } do |promotions|
    # Promotions List（次级菜单第一项，顶级落地）
    promotions.add :promotions_list,
                  label: 'admin.promotions.promotions_list',
                  url: :admin_promotions_path,
                  position: 5,
                  active: -> { controller_name == 'promotions' && action_name == 'index' }
    # Gift Cards
    promotions.add :gift_cards,
                  label: :gift_cards,
                  url: :admin_gift_cards_path,
                  position: 10,
                  active: -> { %w[gift_cards gift_card_batches].include?(controller_name) }
  end

  # Reports — P6：顶级落地 = Reports List
  sidebar_nav.add :reports,
          label: :reports,
          url: :admin_reports_path,
          icon: 'chart-bar',
          position: 60,
          landing: :reports_list,
          if: -> { can?(:manage, PallasTrade::Report) } do |reports|
    reports.add :reports_list,
                label: 'admin.reports.reports_list',
                url: :admin_reports_path,
                position: 5,
                active: -> { controller_name == 'reports' && action_name == 'index' }
  end

  # Emails — top-level menu with submenu（config / scenarios / templates / outbox / inbox）
  sidebar_nav.add :emails,
          label: :emails,
          url: :admin_emails_path,
          icon: 'send',
          position: 70,
          landing: :email_settings,
          if: -> { can?(:manage, current_store) } do |emails|
    # Email configuration（SMTP, from address, reply switch）— 顶级落地
    emails.add :email_settings,
               label: 'admin.emails.settings',
               url: :admin_emails_path,
               position: 10,
               active: -> { controller_name == 'emails' }

    # Notification scenarios (payment success, payment reminder, order status, back in stock, ...)
    emails.add :notification_scenarios,
               label: 'admin.emails.notification_scenarios',
               url: :admin_email_notification_scenarios_path,
               position: 20,
               active: -> { controller_name == 'email_notification_scenarios' }

    # Email templates (content editing)
    emails.add :templates,
               label: 'admin.emails.templates',
               url: :admin_email_templates_path,
               position: 30,
               active: -> { %w[email_templates].include?(controller_name) }

    # Outbox (outgoing send log)
    emails.add :outbox,
               label: 'admin.emails.outbox',
               url: :admin_email_logs_path,
               position: 40,
               active: -> { %w[email_logs].include?(controller_name) }

    # Inbox (complaints, feedback, inbound replies)
    emails.add :inbox,
               label: 'admin.emails.inbox',
               url: :admin_contact_messages_path,
               position: 50,
               active: -> { %w[contact_messages].include?(controller_name) }
  end

  # Blog — CMS content management（posts list / editor）— P6：顶级落地 = Blog List
  sidebar_nav.add :blog,
          label: :blog,
          url: :admin_posts_path,
          icon: 'news',
          position: 75,
          landing: :blog_list,
          if: -> { can?(:manage, PallasTrade::Post) } do |blog|
    blog.add :blog_list,
             label: 'admin.blog.blog_list',
             url: :admin_posts_path,
             position: 5,
             active: -> { controller_name == 'posts' && action_name == 'index' }
  end

  # ===============================================
  # P6：设置区融入主区 —— 以下均为统一 sidebar 树的一级可收拉菜单，
  # 多页面模块带子菜单（landing = 第一个子项），单页面模块保持叶子项。
  # ===============================================

  # Section divider（仅视觉分隔）
  sidebar_nav.add :settings_section,
          section_label: 'Settings',
          position: 90

  # PALLAS-CUSTOM: 多店铺管理（2026-08-17）——店铺列表
  sidebar_nav.add :stores,
          label: 'admin.stores.title',
          url: :admin_stores_path,
          icon: 'building-store',
          position: 94,
          active: -> { controller_name == 'stores' && action_name == 'index' },
          if: -> { can?(:manage, PallasTrade::Store) }

  # Store Details（单页，叶子项）
  sidebar_nav.add :general_settings,
          label: :store_details,
          url: -> { PallasTrade.edit_admin_store_path(section: 'general-settings') },
          icon: 'building-store',
          position: 95,
          active: -> { controller_name == 'stores' && params[:section] == 'general-settings' },
          if: -> { can?(:manage, current_store) }

  # Users — P6 顶级落地 = Admin Users
  sidebar_nav.add :users,
          label: :users,
          url: :admin_admin_users_path,
          icon: 'users',
          position: 100,
          landing: :admin_users,
          if: -> { can?(:manage, PallasTrade.admin_user_class) } do |users|
    users.add :admin_users,
              label: 'admin.users.admin_users',
              url: :admin_admin_users_path,
              position: 5,
              active: -> { controller_name == 'admin_users' }
    users.add :invitations,
              label: :invitations,
              url: :admin_invitations_path,
              position: 10,
              active: -> { controller_name == 'invitations' },
              if: -> { can?(:manage, PallasTrade::Invitation) }
    users.add :roles,
              label: :roles,
              url: :admin_roles_path,
              position: 20,
              active: -> { controller_name == 'roles' },
              if: -> { can?(:manage, PallasTrade::Role) }
  end

  # Policies（单页，叶子项）
  sidebar_nav.add :policies,
          label: :policies,
          url: :admin_policies_path,
          icon: 'list-check',
          position: 105,
          active: -> { controller_name == 'policies' },
          if: -> { can?(:manage, PallasTrade::Policy) }

  # Storefront setup（单页，叶子项）
  sidebar_nav.add :storefront,
          label: 'admin.storefront',
          url: :admin_storefront_path,
          icon: 'building-store',
          position: 110,
          active: -> { controller_name == 'storefront' },
          if: -> { can?(:update, current_store) }

  # Channels（单页，叶子项）
  sidebar_nav.add :channels,
          label: :channels,
          url: :admin_channels_path,
          icon: 'broadcast',
          position: 115,
          active: -> { controller_name == 'channels' },
          if: -> { can?(:manage, PallasTrade::Channel) }

  # Payment Methods（单页，叶子项）
  sidebar_nav.add :payment_methods,
          label: :payments,
          url: :admin_payment_methods_path,
          icon: 'credit-card',
          position: 120,
          active: -> { controller_name == 'payment_methods' },
          if: -> { can?(:manage, PallasTrade::PaymentMethod) }

  # Markets（单页，叶子项）
  sidebar_nav.add :markets,
          label: :markets,
          url: :admin_markets_path,
          icon: 'world',
          position: 125,
          active: -> { controller_name == 'markets' },
          if: -> { can?(:manage, PallasTrade::Market) }

  # Zones（单页，叶子项）
  sidebar_nav.add :zones,
          label: :zones,
          url: :admin_zones_path,
          icon: 'map-2',
          position: 130,
          active: -> { %w[zones countries states].include?(controller_name) },
          if: -> { can?(:manage, PallasTrade::Zone) }

  # Shipping — P6 顶级落地 = Shipping Methods
  sidebar_nav.add :shipping,
          label: :shipping,
          url: :admin_shipping_methods_path,
          icon: 'truck',
          position: 135,
          landing: :shipping_methods,
          if: -> { can?(:manage, PallasTrade::ShippingMethod) } do |shipping|
    shipping.add :shipping_methods,
                 label: :shipping_methods,
                 url: :admin_shipping_methods_path,
                 position: 5,
                 active: -> { controller_name == 'shipping_methods' && action_name == 'index' },
                 if: -> { can?(:manage, PallasTrade::ShippingMethod) }
    shipping.add :shipping_categories,
                 label: :shipping_categories,
                 url: :admin_shipping_categories_path,
                 position: 10,
                 active: -> { controller_name == 'shipping_categories' },
                 if: -> { can?(:manage, PallasTrade::ShippingCategory) }
  end

  # Tax — P6 顶级落地 = Tax Rates
  sidebar_nav.add :tax,
          label: :tax,
          url: :admin_tax_rates_path,
          icon: 'receipt-tax',
          position: 140,
          landing: :tax_rates,
          if: -> { can?(:manage, PallasTrade::TaxRate) } do |tax|
    tax.add :tax_rates,
            label: :tax_rates,
            url: :admin_tax_rates_path,
            position: 5,
            active: -> { controller_name == 'tax_rates' && action_name == 'index' },
            if: -> { can?(:manage, PallasTrade::TaxRate) }
    tax.add :tax_categories,
            label: :tax_categories,
            url: :admin_tax_categories_path,
            position: 10,
            active: -> { controller_name == 'tax_categories' },
            if: -> { can?(:manage, PallasTrade::TaxCategory) }
  end

  # Return Settings — P6 顶级落地 = Return Authorization Reasons
  sidebar_nav.add :return_settings,
          label: :returns,
          url: :admin_return_authorization_reasons_path,
          icon: 'receipt-refund',
          position: 145,
          landing: :return_authorization_reasons,
          if: -> { can?(:manage, PallasTrade::ReturnAuthorizationReason) } do |return_settings|
    return_settings.add :return_authorization_reasons,
                        label: :return_authorization_reasons,
                        url: :admin_return_authorization_reasons_path,
                        position: 5,
                        active: -> { controller_name == 'return_authorization_reasons' },
                        if: -> { can?(:manage, PallasTrade::ReturnAuthorizationReason) }
    return_settings.add :refund_reasons,
                        label: :refund_reasons,
                        url: :admin_refund_reasons_path,
                        position: 10,
                        active: -> { controller_name == 'refund_reasons' },
                        if: -> { can?(:manage, PallasTrade::RefundReason) }
    return_settings.add :reimbursement_types,
                        label: :reimbursement_types,
                        url: :admin_reimbursement_types_path,
                        position: 20,
                        active: -> { controller_name == 'reimbursement_types' },
                        if: -> { can?(:manage, PallasTrade::ReimbursementType) }
  end

  # Stock Locations（单页，叶子项）
  sidebar_nav.add :stock_locations,
          label: :stock_locations,
          url: :admin_stock_locations_path,
          icon: 'map-pin',
          position: 150,
          active: -> { controller_name == 'stock_locations' },
          if: -> { can?(:manage, PallasTrade::StockLocation) }

  # Metafield Definitions（单页，叶子项）
  sidebar_nav.add :metafield_definitions,
          label: :metafield_definitions,
          url: :admin_metafield_definitions_path,
          icon: 'list-details',
          position: 155,
          active: -> { controller_name == 'metafield_definitions' },
          if: -> { can?(:manage, PallasTrade::MetafieldDefinition) }

  # Audit Log — P6 顶级落地 = Audit Log
  sidebar_nav.add :audits,
          label: 'admin.audit_log',
          url: :admin_audits_path,
          icon: 'history',
          position: 160,
          landing: :audit_log,
          if: -> {
            # Only show if audits feature exists
            can?(:manage, current_store) &&
            PallasTrade::Core::Engine.routes.url_helpers.respond_to?(:admin_audits_path)
          } do |audits|
    audits.add :audit_log,
               label: 'admin.audit_log',
               url: :admin_audits_path,
               position: 5,
               active: -> { controller_name == 'audits' }
    audits.add :exports,
               label: :exports,
               url: :admin_exports_path,
               position: 10,
               active: -> { controller_name == 'exports' },
               if: -> { can?(:manage, PallasTrade::Export) }
    audits.add :imports,
               label: :imports,
               url: :admin_imports_path,
               position: 20,
               active: -> { controller_name == 'imports' },
               if: -> { can?(:manage, PallasTrade::Import) }
  end

  # Developers — P6 顶级落地 = API Keys
  sidebar_nav.add :developers,
          label: :developers,
          url: :admin_api_keys_path,
          icon: 'terminal',
          position: 165,
          landing: :api_keys,
          if: -> { can?(:manage, PallasTrade::ApiKey) } do |developers|
    developers.add :api_keys,
                   label: :api_keys,
                   url: :admin_api_keys_path,
                   position: 5,
                   active: -> { controller_name == 'api_keys' },
                   if: -> { can?(:manage, PallasTrade::ApiKey) }
    developers.add :webhook_endpoints,
                   label: :webhook_endpoints,
                   url: :admin_webhook_endpoints_path,
                   position: 10,
                   active: -> { %w[webhook_endpoints webhook_deliveries].include?(controller_name) },
                   if: -> { can?(:manage, PallasTrade::WebhookEndpoint) }
    developers.add :allowed_origins,
                   label: :allowed_origins,
                   url: :admin_allowed_origins_path,
                   position: 20,
                   active: -> { controller_name == 'allowed_origins' },
                   if: -> { can?(:manage, PallasTrade::AllowedOrigin) }
    developers.add :redirects,
                   label: :redirects,
                   url: :admin_redirects_path,
                   position: 30,
                   active: -> { controller_name == 'redirects' },
                   if: -> { can?(:manage, PallasTrade::Redirect) }
  end

  # Back-in-stock subscriptions（customer notifications，单页叶子项）
  sidebar_nav.add :back_in_stock_subscriptions,
          label: 'admin.back_in_stock_subscriptions',
          url: :admin_back_in_stock_subscriptions_path,
          icon: 'bell',
          position: 170,
          active: -> { controller_name == 'back_in_stock_subscriptions' },
          if: -> { can?(:manage, PallasTrade::BackInStockSubscription) }

  # Abandoned cart notifications（P0-3 弃单恢复，单页叶子项）
  sidebar_nav.add :abandoned_cart_notifications,
          label: 'admin.abandoned_cart_notifications.title',
          url: :admin_abandoned_cart_notifications_path,
          icon: 'shopping-cart-down',
          position: 171,
          active: -> { controller_name == 'abandoned_cart_notifications' },
          if: -> { can?(:manage, PallasTrade::AbandonedCartNotification) }

  # Reviews（P0-4 产品评论，单页叶子项）
  sidebar_nav.add :reviews,
          label: 'admin.reviews.title',
          url: :admin_reviews_path,
          icon: 'star',
          position: 172,
          active: -> { controller_name == 'reviews' },
          if: -> { can?(:manage, PallasTrade::Review) }

  # Edit Profile（单页叶子项）
  sidebar_nav.add :edit_profile,
          label: 'admin.edit_profile',
          url: :edit_admin_profile_path,
          icon: 'user-scan',
          position: 200,
          active: -> { controller_name == 'profile' && action_name == 'edit' }

  # PALLAS-CUSTOM: 可视化菜单配置模块（P4 权限体系重构）
  sidebar_nav.add :menu_configs,
          label: 'admin.menu_configs.title',
          url: :admin_menu_configs_path,
          icon: 'layout-navbar',
          position: 175,
          active: -> { controller_name == 'menu_configs' },
          if: -> { can?(:manage, current_store) }

  # ===============================================
  # Page Tab Navigations
  # ===============================================

  # Tax Tab Navigation
  tax_tabs_nav = PallasTrade.admin.navigation.tax_tabs

  tax_tabs_nav.add :tax_rates,
          label: :tax_rates,
          url: :admin_tax_rates_path,
          position: 10,
          if: -> { can?(:manage, PallasTrade::TaxRate) }

  tax_tabs_nav.add :tax_categories,
          label: :tax_categories,
          url: :admin_tax_categories_path,
          position: 20,
          if: -> { can?(:manage, PallasTrade::TaxCategory) }

  # Shipping Tab Navigation
  shipping_tabs_nav = PallasTrade.admin.navigation.shipping_tabs

  shipping_tabs_nav.add :shipping_methods,
          label: :shipping_methods,
          url: :admin_shipping_methods_path,
          position: 10,
          active: -> { controller_name == 'shipping_methods' && action_name == 'index' },
          if: -> { can?(:manage, PallasTrade::ShippingMethod) }

  shipping_tabs_nav.add :shipping_categories,
          label: :shipping_categories,
          url: :admin_shipping_categories_path,
          position: 20,
          if: -> { can?(:manage, PallasTrade::ShippingCategory) }

  # Team Tab Navigation
  team_tabs_nav = PallasTrade.admin.navigation.team_tabs

  team_tabs_nav.add :admin_users,
          label: :users,
          url: :admin_admin_users_path,
          position: 10,
          if: -> { can?(:manage, PallasTrade.admin_user_class) }

  team_tabs_nav.add :invitations,
          label: :invitations,
          url: :admin_invitations_path,
          position: 20,
          if: -> { can?(:manage, PallasTrade::Invitation) }

  team_tabs_nav.add :roles,
          label: :roles,
          url: :admin_roles_path,
          position: 30,
          if: -> { can?(:manage, PallasTrade::Role) }

  # Stock Tab Navigation
  stock_tabs_nav = PallasTrade.admin.navigation.stock_tabs

  stock_tabs_nav.add :stock_items,
          label: :stock_items,
          url: :admin_stock_items_path,
          position: 10,
          active: -> { controller_name == 'stock_items' },
          if: -> { can?(:manage, PallasTrade::StockItem) }

  stock_tabs_nav.add :stock_movements,
          label: :stock_movements,
          url: :admin_stock_movements_path,
          position: 20,
          active: -> { controller_name == 'stock_movements' },
          if: -> { can?(:manage, PallasTrade::StockMovement) }

  stock_tabs_nav.add :stock_transfers,
          label: :stock_transfers,
          url: :admin_stock_transfers_path,
          position: 30,
          active: -> { controller_name == 'stock_transfers' },
          if: -> { can?(:manage, PallasTrade::StockTransfer) }

  # Returns and Refunds Tab Navigation
  returns_tabs_nav = PallasTrade.admin.navigation.returns_tabs

  returns_tabs_nav.add :return_authorization_reasons,
          label: :return_authorization_reasons,
          url: :admin_return_authorization_reasons_path,
          position: 10,
          if: -> { can?(:manage, PallasTrade::ReturnAuthorizationReason) }

  returns_tabs_nav.add :refund_reasons,
          label: :refund_reasons,
          url: :admin_refund_reasons_path,
          position: 20,
          if: -> { can?(:manage, PallasTrade::RefundReason) }

  returns_tabs_nav.add :reimbursement_types,
          label: :reimbursement_types,
          url: :admin_reimbursement_types_path,
          position: 30,
          if: -> { can?(:manage, PallasTrade::ReimbursementType) }

  # Developers Tab Navigation
  developers_tabs_nav = PallasTrade.admin.navigation.developers_tabs

  developers_tabs_nav.add :api_keys,
          label: :api_keys,
          url: :admin_api_keys_path,
          position: 10,
          active: -> { controller_name == 'api_keys' },
          if: -> { can?(:manage, PallasTrade::ApiKey) }

  developers_tabs_nav.add :webhook_endpoints,
          label: :webhook_endpoints,
          url: :admin_webhook_endpoints_path,
          position: 20,
          active: -> { %w[webhook_endpoints webhook_deliveries].include?(controller_name) },
          if: -> { can?(:manage, PallasTrade::WebhookEndpoint) }

  developers_tabs_nav.add :allowed_origins,
          label: :allowed_origins,
          url: :admin_allowed_origins_path,
          position: 30,
          active: -> { controller_name == 'allowed_origins' },
          if: -> { can?(:manage, PallasTrade::AllowedOrigin) }

  developers_tabs_nav.add :redirects,
          label: :redirects,
          url: :admin_redirects_path,
          position: 40,
          active: -> { controller_name == 'redirects' },
          if: -> { can?(:manage, PallasTrade::Redirect) }

  # Audit Tab Navigation
  audit_tabs_nav = PallasTrade.admin.navigation.audit_tabs

  audit_tabs_nav.add :audit_log,
          label: 'admin.audit_log',
          url: :admin_audits_path,
          position: 10,
          active: -> { controller_name == 'audits' },
          if: -> { can?(:manage, current_store) }

  audit_tabs_nav.add :exports,
          label: :exports,
          url: :admin_exports_path,
          position: 20,
          active: -> { controller_name == 'exports' },
          if: -> { can?(:manage, PallasTrade::Export) }

  audit_tabs_nav.add :imports,
          label: :imports,
          url: :admin_imports_path,
          position: 30,
          active: -> { controller_name == 'imports' },
          if: -> { can?(:manage, PallasTrade::Import) }
end
