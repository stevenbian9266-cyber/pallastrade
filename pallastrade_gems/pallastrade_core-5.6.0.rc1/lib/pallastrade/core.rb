require 'ostruct'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'active_job/railtie'
require 'active_model/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_text/engine'
require 'action_cable/engine'
require 'pagy'

require 'mail'
require 'action_mailer/railtie'


require 'acts_as_list'
require 'acts-as-taggable-on'
require 'awesome_nested_set'
require 'cancan'
require 'countries/global'
require 'friendly_id'
require 'jwt'
require 'monetize'
require 'mobility'
require 'name_of_person'
require 'paranoia'
require 'ransack'
require 'state_machines-activerecord'
require 'active_storage_validations'
require 'wannabe_bool'
require 'geocoder'

require 'safely_block'
require 'ar_lazy_preload'
require 'sqids'

# This is required because ActiveModel::Validations#invalid? conflicts with the
# invalid state of a Payment. In the future this should be removed.
StateMachines::Machine.ignore_method_conflicts = true

module PallasTrade
  mattr_accessor :base_class, :user_class, :admin_user_class,
                 :private_storage_service_name, :public_storage_service_name,
                 :cdn_host, :root_domain, :searcher_class, :events_adapter_class, :queues,
                 :google_places_api_key

  def self.base_class(constantize: true)
    @@base_class ||= 'PallasTrade::Base'
    if @@base_class.is_a?(Class)
      raise 'PallasTrade.base_class MUST be a String or Symbol object, not a Class object.'
    elsif @@base_class.is_a?(String) || @@base_class.is_a?(Symbol)
      constantize ? @@base_class.to_s.constantize : @@base_class.to_s
    end
  end

  def self.user_class(constantize: true)
    if @@user_class.is_a?(Class)
      raise 'PallasTrade.user_class MUST be a String or Symbol object, not a Class object.'
    elsif @@user_class.is_a?(String) || @@user_class.is_a?(Symbol)
      constantize ? @@user_class.to_s.constantize : @@user_class.to_s
    end
  end

  def self.admin_user_class(constantize: true)
    if @@admin_user_class.is_a?(Class)
      raise 'PallasTrade.admin_user_class MUST be a String or Symbol object, not a Class object.'
    elsif @@admin_user_class.is_a?(String) || @@admin_user_class.is_a?(Symbol)
      constantize ? @@admin_user_class.to_s.constantize : @@admin_user_class.to_s
    end
  end

  def self.private_storage_service_name
    if @@private_storage_service_name
      if @@private_storage_service_name.is_a?(String) || @@private_storage_service_name.is_a?(Symbol)
        @@private_storage_service_name.to_sym
      end
    else
      Rails.application.config.active_storage.service
    end
  end

  def self.public_storage_service_name
    if @@public_storage_service_name
      if @@public_storage_service_name.is_a?(String) || @@public_storage_service_name.is_a?(Symbol)
        @@public_storage_service_name.to_sym
      end
    else
      Rails.application.config.active_storage.service
    end
  end

  def self.root_domain
    @@root_domain
  end

  def self.queues
    @@queues ||= OpenStruct.new(
      default: :default,
      events: :default,
      exports: :default,
      images: :default,
      imports: :default,
      products: :default,
      reports: :default,
      variants: :default,
      taxons: :default,
      stock_location_stock_items: :default,
      coupon_codes: :default,
      themes: :default,
      addresses: :default,
      gift_cards: :default,
      webhooks: :default,
      payment_webhooks: :default,
      api_keys: :default,
      search: :default,
      stock_reservations: :default
    )
  end

  # @deprecated PallasTrade.searcher_class is deprecated and will be removed in PallasTrade 5.5. Use PallasTrade.search_provider instead.
  def self.searcher_class=(value)
    PallasTrade::Deprecation.warn('PallasTrade.searcher_class is deprecated and will be removed in PallasTrade 5.5. Use PallasTrade.search_provider instead.')
    @@searcher_class = value
  end

  def self.searcher_class(constantize: true)
    @@searcher_class
  end

  # Search provider class name. Controls product search, filtering, and faceted navigation.
  #
  #   PallasTrade.search_provider = 'PallasTrade::SearchProvider::Meilisearch'
  #
  def self.search_provider
    @@search_provider ||= 'PallasTrade::SearchProvider::Database'
  end

  def self.search_provider=(value)
    @@search_provider = value.to_s
  end

  # Returns the events adapter class used for publishing and subscribing to events.
  #
  # @example Using a custom adapter
  #   PallasTrade.events_adapter_class = 'MyApp::Events::KafkaAdapter'
  #
  # @param constantize [Boolean] whether to return the class or the string
  # @return [Class, String] the adapter class or its name
  def self.events_adapter_class(constantize: true)
    @@events_adapter_class ||= 'PallasTrade::Events::Adapters::ActiveSupportNotifications'

    if @@events_adapter_class.is_a?(Class)
      raise 'PallasTrade.events_adapter_class MUST be a String or Symbol object, not a Class object.'
    elsif @@events_adapter_class.is_a?(String) || @@events_adapter_class.is_a?(Symbol)
      constantize ? @@events_adapter_class.to_s.constantize : @@events_adapter_class.to_s
    end
  end

  def self.google_places_api_key
    @@google_places_api_key
  end

  def self.always_use_translations?
    PallasTrade::Config.always_use_translations
  end

  def self.use_translations?
    PallasTrade::Config.always_use_translations || PallasTrade::Current.content_locale != I18n.locale.name
  end

  # Mobility +column_fallback+ option shared by every translatable model:
  # read, write and query the base (untranslated) column when the target
  # locale is the request's content locale — see PallasTrade::Current#content_locale.
  # Evaluated on every translated attribute read, so it must stay
  # allocation-free and must not touch the database (Symbol#name returns the
  # frozen interned string; Mobility always passes Symbol locales).
  def self.mobility_column_fallback
    return false if always_use_translations?

    ->(locale) { locale.name == PallasTrade::Current.content_locale }
  end

  # Used to configure PallasTrade.
  #
  # Example:
  #
  #   PallasTrade.config do |config|
  #     config.track_inventory_levels = false
  #   end
  #
  # This method is defined within the core gem on purpose.
  # Some people may only wish to use the Core part of PallasTrade.
  def self.config
    Rails.application.config.after_initialize do
      yield(PallasTrade::Config)
    end
  end

  # Used to set dependencies for PallasTrade.
  #
  # Example:
  #
  #   PallasTrade.dependencies do |dependency|
  #     dependency.cart_add_item_service = MyCustomAddToCart
  #   end
  #
  # This method is defined within the core gem on purpose.
  # Some people may only wish to use the Core part of PallasTrade.
  def self.dependencies
    yield(PallasTrade::Dependencies)
  end

  # Environment accessors for easier configuration access
  # Instead of Rails.application.config.spree.payment_methods
  # you can use PallasTrade.payment_methods

  def self.calculators
    Rails.application.config.spree.calculators
  end

  def self.calculators=(value)
    Rails.application.config.spree.calculators = value
  end

  def self.validators
    Rails.application.config.spree.validators
  end

  def self.validators=(value)
    Rails.application.config.spree.validators = value
  end

  def self.payment_methods
    Rails.application.config.spree.payment_methods
  end

  def self.payment_methods=(value)
    Rails.application.config.spree.payment_methods = value
  end

  def self.adjusters
    Rails.application.config.spree.adjusters
  end

  def self.adjusters=(value)
    Rails.application.config.spree.adjusters = value
  end

  def self.stock_splitters
    Rails.application.config.spree.stock_splitters
  end

  def self.stock_splitters=(value)
    Rails.application.config.spree.stock_splitters = value
  end

  def self.order_routing
    Rails.application.config.spree.order_routing
  end

  def self.order_routing=(value)
    Rails.application.config.spree.order_routing = value
  end

  def self.promotions
    Rails.application.config.spree.promotions
  end

  def self.promotions=(value)
    Rails.application.config.spree.promotions = value
  end

  def self.line_item_comparison_hooks
    Rails.application.config.spree.line_item_comparison_hooks
  end

  def self.line_item_comparison_hooks=(value)
    Rails.application.config.spree.line_item_comparison_hooks = value
  end

  def self.data_feed_types
    Rails.application.config.spree.data_feed_types
  end

  def self.data_feed_types=(value)
    Rails.application.config.spree.data_feed_types = value
  end

  def self.export_types
    Rails.application.config.spree.export_types
  end

  def self.export_types=(value)
    Rails.application.config.spree.export_types = value
  end

  def self.import_types
    Rails.application.config.spree.import_types
  end

  def self.import_types=(value)
    Rails.application.config.spree.import_types = value
  end

  def self.taxon_rules
    Rails.application.config.spree.taxon_rules
  end

  def self.taxon_rules=(value)
    Rails.application.config.spree.taxon_rules = value
  end

  # Class-name strings (`'PallasTrade::Product'`, `'PallasTrade::Order'`,
  # `PallasTrade.user_class.to_s`, plus any registered by apps) for resources that
  # expose tags via `acts_as_taggable_on :tags`. Used by the Admin API
  # `/tags` autocomplete endpoint to validate `taggable_type`. Apps extend
  # the list in an initializer:
  #
  #   PallasTrade.taggable_types << 'MyApp::Vendor'
  def self.taggable_types
    Rails.application.config.spree.taggable_types
  end

  def self.taggable_types=(value)
    Rails.application.config.spree.taggable_types = value
  end

  def self.reports
    Rails.application.config.spree.reports
  end

  def self.reports=(value)
    Rails.application.config.spree.reports = value
  end

  # Registry of the Getting Started onboarding tasks shown on the admin
  # dashboard. See {PallasTrade::SetupTasks} for the extension API.
  #
  # @return [PallasTrade::SetupTasks]
  def self.store_setup_tasks
    @store_setup_tasks ||= PallasTrade::SetupTasks.new
  end

  def self.translatable_resources
    Rails.application.config.spree.translatable_resources
  end

  def self.translatable_resources=(value)
    Rails.application.config.spree.translatable_resources = value
  end

  def self.metafields
    Rails.application.config.spree.metafields
  end

  def self.integrations
    Rails.application.config.spree.integrations
  end

  def self.integrations=(value)
    Rails.application.config.spree.integrations = value
  end

  # Event subscribers that handle lifecycle and custom events
  # @example Adding a custom subscriber
  #   PallasTrade.subscribers << MyApp::OrderNotificationSubscriber
  # @example Removing a built-in subscriber
  #   PallasTrade.subscribers.delete(PallasTrade::ExportSubscriber)
  def self.subscribers
    Rails.application.config.spree.subscribers
  end

  def self.subscribers=(value)
    Rails.application.config.spree.subscribers = value
  end

  def self.pricing
    Rails.application.config.spree.pricing
  end

  def self.pricing=(value)
    Rails.application.config.spree.pricing = value
  end

  # Registry of authentication strategy classes for the Store API.
  # @return [PallasTrade::Authentication::StrategyRegistry]
  # @example Registering a third-party identity provider
  #   PallasTrade.store_authentication_strategies.add(:auth0, MyApp::Auth::Auth0Strategy)
  # @example Removing a strategy
  #   PallasTrade.store_authentication_strategies.remove(:email)
  def self.store_authentication_strategies
    Rails.application.config.spree.store_authentication_strategies
  end

  # @param value [PallasTrade::Authentication::StrategyRegistry] the registry to use for Store API authentication dispatch
  # @return [PallasTrade::Authentication::StrategyRegistry] the assigned registry
  def self.store_authentication_strategies=(value)
    Rails.application.config.spree.store_authentication_strategies = value
  end

  # Registry of authentication strategy classes for the Admin API.
  # @return [PallasTrade::Authentication::StrategyRegistry]
  # @example Registering an SSO strategy for admin users
  #   PallasTrade.admin_authentication_strategies.add(:okta, MyApp::Auth::OktaStrategy)
  def self.admin_authentication_strategies
    Rails.application.config.spree.admin_authentication_strategies
  end

  # @param value [PallasTrade::Authentication::StrategyRegistry] the registry to use for Admin API authentication dispatch
  # @return [PallasTrade::Authentication::StrategyRegistry] the assigned registry
  def self.admin_authentication_strategies=(value)
    Rails.application.config.spree.admin_authentication_strategies = value
  end

  def self.analytics
    @analytics ||= AnalyticsConfig.new
  end

  # Group analytics configuration options together, but still make it backwards compatible.
  class AnalyticsConfig
    def events
      Rails.application.config.spree.analytics_events
    end

    def events=(value)
      Rails.application.config.spree.analytics_events = value
    end

    def handlers
      Rails.application.config.spree.analytics_event_handlers
    end

    def handlers=(value)
      Rails.application.config.spree.analytics_event_handlers = value
    end
  end

  # Permission configuration accessor for managing role-to-permission-set mappings.
  #
  # @example Assigning permission sets to a role
  #   PallasTrade.permissions.assign(:customer_service, [
  #     PallasTrade::PermissionSets::OrderDisplay,
  #     PallasTrade::PermissionSets::UserManagement
  #   ])
  #
  # @example Clearing permission sets from a role
  #   PallasTrade.permissions.clear(:customer_service)
  #
  # @return [PallasTrade::PermissionConfiguration] the permission configuration instance
  def self.permissions
    @permissions ||= PermissionConfiguration.new
  end

  # Ransack configuration accessor for managing custom ransackable attributes,
  # associations, and scopes across Spree models.
  #
  # @example Adding custom searchable fields
  #   PallasTrade.ransack.add_attribute(PallasTrade::Product, :vendor_id)
  #   PallasTrade.ransack.add_scope(PallasTrade::Product, :by_vendor)
  #   PallasTrade.ransack.add_association(PallasTrade::Product, :vendor)
  #
  # @return [PallasTrade::RansackConfiguration] the ransack configuration instance
  def self.ransack
    @ransack ||= RansackConfiguration.new
  end

  class << self
    # Dynamic methods for core dependencies
    #
    # @example Getting a dependency (returns resolved class)
    #   PallasTrade.cart_add_item_service.call(order: order, variant: variant)
    #
    # @example Setting a dependency
    #   PallasTrade.cart_add_item_service = MyApp::CartAddItem
    def method_missing(method_name, *args, &block)
      base_name = method_name.to_s.chomp('=').to_sym

      return super unless core_dependency?(base_name)

      if method_name.to_s.end_with?('=')
        PallasTrade::Dependencies.send(method_name, args.first)
      else
        # Returns resolved class (not string)
        PallasTrade::Dependencies.send("#{method_name}_class")
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      base_name = method_name.to_s.chomp('=').to_sym
      core_dependency?(base_name) || super
    end

    private

    def core_dependency?(name)
      defined?(PallasTrade::Dependencies) &&
        PallasTrade::Dependencies.class::INJECTION_POINTS.include?(name)
    end
  end

  module Core
    class GatewayError < RuntimeError; end
    class DestroyWithOrdersError < StandardError; end
  end
end

require 'pallastrade/core/version'

require 'pallastrade/core/number_generator'
require 'pallastrade/migrations'
require 'pallastrade/translation_migrations'
require 'pallastrade/core/engine'

require 'pallastrade/i18n'
require 'pallastrade/localized_number'
require 'pallastrade/translations'
require 'pallastrade/money'
require 'pallastrade/permitted_attributes'
require 'pallastrade/service_module'
require 'pallastrade/analytics'
require 'pallastrade/events'
require 'pallastrade/webhooks'

require 'pallastrade/core/partials'
require 'pallastrade/core/controller_helpers/auth'
require 'pallastrade/core/controller_helpers/order'
require 'pallastrade/core/controller_helpers/store'
require 'pallastrade/core/controller_helpers/strong_parameters'
require 'pallastrade/core/controller_helpers/locale'
require 'pallastrade/core/controller_helpers/currency'
require 'pallastrade/core/controller_helpers/turbo'

require 'pallastrade/core/preferences/store'
require 'pallastrade/core/preferences/scoped_store'
require 'pallastrade/core/preferences/runtime_configuration'
require 'pallastrade/core/preferences/masking'

require 'pallastrade/core/permission_configuration'
require 'pallastrade/core/ransack_configuration'
require 'pallastrade/core/pricing/context'
require 'pallastrade/core/pricing/resolver'
