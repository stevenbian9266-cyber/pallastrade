require_relative 'dependencies'
require_relative 'configuration'

module PallasTrade
  module Core
    class Engine < ::Rails::Engine
      Environment = Struct.new(:calculators,
                               :validators,
                               :preferences,
                               :dependencies,
                               :payment_methods,
                               :adjusters,
                               :stock_splitters,
                               :order_routing,
                               :promotions,
                               :pricing,
                               :line_item_comparison_hooks,
                               :data_feed_types,
                               :export_types,
                               :import_types,
                               :taxon_rules,
                               :themes,
                               :theme_layout_sections,
                               :pages,
                               :page_sections,
                               :page_blocks,
                               :reports,
                               :translatable_resources,
                               :taggable_types,
                               :metafields,
                               :analytics_events,
                               :analytics_event_handlers,
                               :integrations,
                               :subscribers,
                               :store_authentication_strategies,
                               :admin_authentication_strategies)
      PallasTradeCalculators = Struct.new(:shipping_methods, :tax_rates, :promotion_actions_create_adjustments, :promotion_actions_create_item_adjustments)
      PromoEnvironment = Struct.new(:rules, :actions)
      PricingEnvironment = Struct.new(:rules)
      OrderRoutingEnvironment = Struct.new(:strategies, :rules)
      PallasTradeValidators = Struct.new(:addresses)
      MetafieldsEnvironment = Struct.new(:types, :enabled_resources)
      isolate_namespace PallasTrade
      engine_name 'pallastrade'

      # Rails infers constants from paths in two places: its Zeitwerk loaders
      # and Action Controller's eager helper inclusion. Configure both before
      # the once autoloader is set up.
      initializer 'pallastrade.inflections', before: :setup_once_autoloader do |app|
        ActiveSupport::Inflector.inflections(:en) do |inflect|
          inflect.acronym 'PallasTrade'
        end

        app.autoloaders.each do |loader|
          loader.inflector.inflect('pallastrade' => 'PallasTrade')
        end
      end

      # Add app/subscribers to autoload paths
      config.paths.add 'app/subscribers', eager_load: true

      # Register bundled ActionMailer previews so they show up at /rails/mailers
      # without the host app having to copy any files.
      initializer 'PallasTrade.mailer_previews' do |app|
        if app.config.action_mailer.show_previews
          app.config.action_mailer.preview_paths << File.expand_path('previews', __dir__)
        end
      end

      initializer 'PallasTrade.environment', before: :load_config_initializers do |app|
        app.config.spree = Environment.new(PallasTradeCalculators.new, PallasTradeValidators.new, PallasTrade::Core::Configuration.new, PallasTrade::Core::Dependencies.new)

        app.config.active_record.yaml_column_permitted_classes ||= []
        app.config.active_record.yaml_column_permitted_classes.concat([Symbol, BigDecimal, ActiveSupport::HashWithIndifferentAccess, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone, Time])
        PallasTrade::Config = app.config.spree.preferences
        PallasTrade::RuntimeConfig = app.config.spree.preferences # for compatibility
        PallasTrade::Dependencies = app.config.spree.dependencies
        PallasTrade::Deprecation = ActiveSupport::Deprecation.new('6.0', 'Spree')
      end

      # I18n's config lives in fiber/thread-local storage that survives across
      # requests on reused server threads, so a request that never assigns its
      # own locale would render in whatever locale the previous request on the
      # same thread set. The i18n gem ships a middleware that resets it after
      # every request; Rails does not install it by default. Mobility's request
      # state needs no counterpart here — Mobility.locale and Spree's
      # Mobility.store_based_fallbacks live in RequestStore, which is cleared
      # per request by request_store's own middleware.
      initializer 'PallasTrade.locale_state_reset' do |app|
        app.middleware.use ::I18n::Middleware
      end

      initializer 'PallasTrade.register.subscribers', before: :load_config_initializers do |app|
        # Initialize subscribers array early so engines can add subscribers via initializers
        app.config.spree.subscribers = []
      end

      initializer 'PallasTrade.register.calculators', before: :after_initialize do |app|
      end

      initializer 'PallasTrade.register.stock_splitters', before: :load_config_initializers do |app|
      end

      initializer 'PallasTrade.register.line_item_comparison_hooks', before: :load_config_initializers do |app|
        app.config.spree.line_item_comparison_hooks = Set.new
      end

      initializer 'PallasTrade.register.payment_methods', after: 'acts_as_list.insert_into_active_record' do |app|
      end

      initializer 'PallasTrade.register.adjustable_adjusters' do |app|
      end

      # Seed the order routing registries early so engines and apps can append
      # their own strategies / rule kinds from initializer files. Core's defaults
      # are concatenated in after_initialize below.
      initializer 'PallasTrade.register.order_routing', before: :load_config_initializers do |app|
        app.config.spree.order_routing = OrderRoutingEnvironment.new
        app.config.spree.order_routing.strategies = []
        app.config.spree.order_routing.rules = []
      end

      initializer 'PallasTrade.register.metafields' do |app|
        app.config.spree.metafields = MetafieldsEnvironment.new
        app.config.spree.metafields.types = []
        app.config.spree.metafields.enabled_resources = []
      end

      # We need to define promotions rules here so extensions and existing apps
      # can add their custom classes on their initializer files
      initializer 'PallasTrade.promo.environment' do |app|
        app.config.spree.promotions = PromoEnvironment.new
        app.config.spree.promotions.rules = []
      end

      initializer 'PallasTrade.promo.register.promotion.calculators' do |app|
      end

      # Pricing configuration for price lists and price rules
      initializer 'PallasTrade.pricing.environment', after: 'PallasTrade.environment' do |app|
        app.config.spree.pricing = PricingEnvironment.new
        app.config.spree.pricing.rules = []
      end

      # Promotion rules need to be evaluated on after initialize otherwise
      # PallasTrade.user_class would be nil and users might experience errors related
      # to malformed model associations (PallasTrade.user_class is only defined on
      # the app initializer)
      config.after_initialize do
        Rails.application.config.spree.calculators.shipping_methods = [
          PallasTrade::Calculator::Shipping::FlatPercentItemTotal,
          PallasTrade::Calculator::Shipping::FlatRate,
          PallasTrade::Calculator::Shipping::FlexiRate,
          PallasTrade::Calculator::Shipping::PerItem,
          PallasTrade::Calculator::Shipping::PriceSack,
          PallasTrade::Calculator::Shipping::DigitalDelivery,
        ]

        Rails.application.config.spree.calculators.tax_rates = [
          PallasTrade::Calculator::DefaultTax
        ]

        Rails.application.config.spree.stock_splitters = [
          PallasTrade::Stock::Splitter::ShippingCategory,
          PallasTrade::Stock::Splitter::Backordered,
          PallasTrade::Stock::Splitter::Digital
        ]

        Rails.application.config.spree.payment_methods = [
          PallasTrade::Gateway::Bogus,
          PallasTrade::Gateway::CustomPaymentSourceMethod,
          PallasTrade::PaymentMethod::Check,
          PallasTrade::PaymentMethod::StoreCredit
        ]

        Rails.application.config.spree.adjusters = [
          PallasTrade::Adjustable::Adjuster::Promotion,
          PallasTrade::Adjustable::Adjuster::Tax
        ]

        # Selectable order routing strategies. The internal Reducer collaborator
        # is intentionally NOT listed — it is not a Strategy::Base. Plugins add
        # their own (or remove Legacy) via this array.
        Rails.application.config.spree.order_routing.strategies.concat [
          PallasTrade::OrderRouting::Strategy::Rules,
          PallasTrade::OrderRouting::Strategy::Legacy
        ]

        # Available order routing rule kinds. STI dispatches at runtime via the
        # +type+ column; this array is the curated allowlist that drives admin
        # pickers and the rule +type+ validation. Plugins append their own.
        Rails.application.config.spree.order_routing.rules.concat [
          PallasTrade::OrderRouting::Rules::PreferredLocation,
          PallasTrade::OrderRouting::Rules::MinimizeSplits,
          PallasTrade::OrderRouting::Rules::DefaultLocation
        ]

        Rails.application.config.spree.calculators.promotion_actions_create_adjustments = [
          PallasTrade::Calculator::FlatPercentItemTotal,
          PallasTrade::Calculator::FlatRate,
          PallasTrade::Calculator::FlexiRate,
          PallasTrade::Calculator::TieredPercent,
          PallasTrade::Calculator::TieredFlatRate
        ]

        Rails.application.config.spree.calculators.promotion_actions_create_item_adjustments = [
          PallasTrade::Calculator::PercentOnLineItem,
          PallasTrade::Calculator::FlatRate,
          PallasTrade::Calculator::FlexiRate
        ]

        Rails.application.config.spree.promotions.rules.concat [
          PallasTrade::Promotion::Rules::Currency,
          PallasTrade::Promotion::Rules::Country,
          PallasTrade::Promotion::Rules::Channel,
          PallasTrade::Promotion::Rules::Market,
          PallasTrade::Promotion::Rules::ItemTotal,
          PallasTrade::Promotion::Rules::Product,
          PallasTrade::Promotion::Rules::User,
          PallasTrade::Promotion::Rules::CustomerGroup,
          PallasTrade::Promotion::Rules::FirstOrder,
          PallasTrade::Promotion::Rules::UserLoggedIn,
          PallasTrade::Promotion::Rules::OneUsePerUser,
          PallasTrade::Promotion::Rules::Taxon,
          PallasTrade::Promotion::Rules::OptionValue,
        ]

        # Default registry. MarketRule is included so existing installs
        # don't lose access to saved rule rows in the admin. ZoneRule is
        # intentionally excluded — Zones are being removed in 6.0 (see
        # docs/plans/6.0-tax-provider.md) and we don't want to invest
        # in admin UI for a model on its way out. The class itself
        # stays so legacy data continues to load; it just doesn't show
        # up in the "Add rule" picker.
        Rails.application.config.spree.pricing.rules.concat [
          PallasTrade::PriceRules::UserRule,
          PallasTrade::PriceRules::CustomerGroupRule,
          PallasTrade::PriceRules::VolumeRule,
          PallasTrade::PriceRules::MarketRule,
          PallasTrade::PriceRules::ChannelRule
        ]

        Rails.application.config.spree.promotions.actions = [
          Promotion::Actions::CreateAdjustment,
          Promotion::Actions::CreateItemAdjustments,
          Promotion::Actions::CreateLineItems,
          Promotion::Actions::FreeShipping
        ]

        Rails.application.config.spree.data_feed_types = [
          PallasTrade::DataFeed::Google
        ]

        Rails.application.config.spree.export_types = [
          PallasTrade::Exports::Products,
          PallasTrade::Exports::ProductTranslations,
          PallasTrade::Exports::Orders,
          PallasTrade::Exports::Customers,
          PallasTrade::Exports::GiftCards,
          PallasTrade::Exports::NewsletterSubscribers,
          PallasTrade::Exports::CouponCodes
        ]

        Rails.application.config.spree.import_types = [
          PallasTrade::Imports::Products,
          PallasTrade::Imports::ProductTranslations,
          PallasTrade::Imports::Customers,
        ]

        Rails.application.config.spree.taxon_rules = [
          PallasTrade::TaxonRules::Tag,
          PallasTrade::TaxonRules::AvailableOn,
          PallasTrade::TaxonRules::Sale,
        ]

        Rails.application.config.spree.reports = [
          PallasTrade::Reports::ProductsPerformance,
          PallasTrade::Reports::SalesTotal
        ]

        Rails.application.config.spree.translatable_resources = [
          PallasTrade::OptionType,
          PallasTrade::OptionValue,
          PallasTrade::Product,
          PallasTrade::Taxon,
          PallasTrade::Taxonomy,
          PallasTrade::Store,
          PallasTrade::Policy
        ]

        # Resources that expose tags via `acts_as_taggable_on :tags`. The
        # Admin API's `/tags` autocomplete endpoint accepts these as
        # `taggable_type`, and the SPA `<TagCombobox>` targets them by name.
        # Extend in an app initializer (after :load_config_initializers) to
        # surface custom taggables — e.g.
        #   Rails.application.config.spree.taggable_types << 'MyApp::Vendor'.
        Rails.application.config.spree.taggable_types = [
          'PallasTrade::Product',
          'PallasTrade::Order',
          PallasTrade.user_class.to_s
        ]

        Rails.application.config.spree.metafields.types = [
          PallasTrade::Metafields::ShortText,
          PallasTrade::Metafields::LongText,
          PallasTrade::Metafields::RichText,
          PallasTrade::Metafields::Number,
          PallasTrade::Metafields::Boolean,
          PallasTrade::Metafields::Json
        ]

        Rails.application.config.spree.metafields.enabled_resources = [
          PallasTrade::Address,
          PallasTrade::Asset,
          PallasTrade::CreditCard,
          PallasTrade::CustomerReturn,
          PallasTrade::GiftCard,
          PallasTrade::Image,
          PallasTrade::LineItem,
          PallasTrade::NewsletterSubscriber,
          PallasTrade::OptionType,
          PallasTrade::OptionValue,
          PallasTrade::Order,
          PallasTrade::Payment,
          PallasTrade::PaymentMethod,
          PallasTrade::PaymentSource,
          PallasTrade::Product,
          PallasTrade::Promotion,
          PallasTrade::Refund,
          PallasTrade::Shipment,
          PallasTrade::ShippingMethod,
          PallasTrade::StockItem,
          PallasTrade::StockTransfer,
          PallasTrade::Store,
          PallasTrade::StoreCredit,
          PallasTrade::TaxRate,
          PallasTrade::Taxon,
          PallasTrade::Taxonomy,
          PallasTrade::Variant,
          PallasTrade.user_class
        ]

        Rails.application.config.spree.analytics_events = {
          product_viewed: 'Product Viewed',
          product_list_viewed: 'Product List Viewed',
          product_searched: 'Product Searched',
          product_added: 'Product Added',
          product_removed: 'Product Removed',

          product_added_to_wishlist: 'Product Added to Wishlist',
          product_removed_from_wishlist: 'Product Removed from Wishlist',

          subscribed_to_newsletter: 'Subscribed to Newsletter',
          unsubscribed_from_newsletter: 'Unsubscribed from Newsletter',

          payment_info_entered: 'Payment Info Entered',
          coupon_entered: 'Coupon Entered',
          coupon_removed: 'Coupon Removed',
          coupon_applied: 'Coupon Applied',
          coupon_denied: 'Coupon Denied',

          checkout_started: 'Checkout Started',
          checkout_email_entered: 'Checkout Email Entered',
          checkout_step_viewed: 'Checkout Step Viewed',
          checkout_step_completed: 'Checkout Step Completed',
          order_completed: 'Order Completed',
        }
        Rails.application.config.spree.analytics_event_handlers = []

        Rails.application.config.spree.integrations = []

        Rails.application.config.spree.validators.addresses = [
          PallasTrade::Addresses::PhoneValidator
        ]

        # Add core event subscribers
        # Other engines add their subscribers in their own after_initialize blocks
        # Note: PallasTrade::EventLogSubscriber is attached in to_prepare (below) so it
        # survives Zeitwerk code reloads in development.
        PallasTrade.subscribers.concat [
          PallasTrade::ExportSubscriber,
          PallasTrade::ReportSubscriber,
          PallasTrade::InvitationEmailSubscriber,
          PallasTrade::AdminUserEmailSubscriber,
          PallasTrade::ProductMetricsSubscriber
        ]

        # Pre-load authentication strategy classes to avoid reflection at request time
        Rails.application.config.spree.store_authentication_strategies = PallasTrade::Authentication::StrategyRegistry.new(
          email: PallasTrade::Authentication::Strategies::EmailPasswordStrategy
        )
        Rails.application.config.spree.admin_authentication_strategies = PallasTrade::Authentication::StrategyRegistry.new(
          email: PallasTrade::Authentication::Strategies::EmailPasswordStrategy
        )
      end

      initializer 'PallasTrade.promo.register.promotions.actions' do |app|
      end

      # filter sensitive information during logging
      initializer 'PallasTrade.params.filter' do |app|
        app.config.filter_parameters += [
          :password,
          :password_confirmation,
          :number,
          :verification_value,
          :client_id,
          :client_secret,
          :refresh_token
        ]
      end

      initializer 'PallasTrade.core.checking_migrations' do |app|
        app.config.after_initialize do
          Migrations.new(config, engine_name).check unless Rails.env.test? || PallasTrade::Config.disable_migration_check
        end
      end

      initializer 'PallasTrade.core.assets' do |app|
        if app.config.respond_to?(:assets)
          app.config.assets.paths << root.join('app/javascript')
          app.config.assets.paths << root.join('vendor/javascript')
          app.config.assets.precompile += %w[pallastrade_core_manifest]
        end
      end

      initializer 'PallasTrade.core.importmap', before: 'importmap' do |app|
        if app.config.respond_to?(:importmap)
          app.config.importmap.paths << root.join('config/importmap.rb')
          # https://github.com/rails/importmap-rails?tab=readme-ov-file#sweeping-the-cache-in-development-and-test
          app.config.importmap.cache_sweepers << root.join('app/javascript')
        end
      end

      # Activate event subscribers after all engines have registered their subscribers
      # This registers an after_initialize callback late, ensuring it runs after all engine callbacks
      # Needed for console, jobs, and other contexts where to_prepare doesn't run
      initializer 'PallasTrade.events.schedule_activation', after: :load_config_initializers do |app|
        app.config.after_initialize do
          PallasTrade::Events.activate!
        end
      end

      config.to_prepare do
        # Ensure spree locale paths are present before decorators
        I18n.load_path.unshift(*(Dir.glob(
          File.join(
            File.dirname(__FILE__), '../../../config/locales', '*.{rb,yml}'
          )
        ) - I18n.load_path))

        # Load application's model / class decorators
        Dir.glob(File.join(File.dirname(__FILE__), '../../../app/**/*_decorator*.rb')) do |c|
          Rails.configuration.cache_classes ? require(c) : load(c)
        end

        # Reset and re-activate event subscribers on code reload
        # activate! will register all subscribers from PallasTrade.subscribers
        # Note: resolve_subscriber in register_subscribers! handles stale class references
        PallasTrade::Events.reset!
        PallasTrade::Events.activate!

        # Re-attach event log subscriber if enabled
        if PallasTrade::Config.events_log_enabled
          require_relative '../../../app/subscribers/pallastrade/event_log_subscriber'
          PallasTrade::EventLogSubscriber.attach_to_notifications
        end
      end
    end
  end
end

require 'pallastrade/core/routes'
require 'pallastrade/core/components'
