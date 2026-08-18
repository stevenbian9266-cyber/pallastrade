# frozen_string_literal: true

require 'uri'

module PallasTrade
  class Store < PallasTrade.base_class
    has_prefix_id :store # PallasTrade-specific: store

    include FriendlyId
    include PallasTrade::TranslatableResource
    include PallasTrade::Metafields
    include PallasTrade::Metadata
    include PallasTrade::Stores::Setup
    include PallasTrade::Stores::Markets
    include PallasTrade::Stores::Channels
    include PallasTrade::Security::Stores if defined?(PallasTrade::Security::Stores)
    include PallasTrade::UserManagement
    include PallasTrade::OrderRouting::HasStrategyPreference

    #
    # Magic methods
    #
    acts_as_paranoid
    friendly_id :code, use: [:slugged], slug_column: :code, routes: :normal

    #
    # Translations
    #
    TRANSLATABLE_FIELDS = %i[name meta_description meta_keywords seo_title customer_support_email
                             address contact_phone].freeze
    translates(*TRANSLATABLE_FIELDS, column_fallback: PallasTrade.mobility_column_fallback)
    self::Translation.class_eval do
      acts_as_paranoid
      # deleted translation values still need to be accessible - remove deleted_at scope
      default_scope { unscope(where: :deleted_at) }
    end

    #
    # Preferences
    #
    # general preferences
    preference :admin_locale, :string
    preference :timezone, :string, default: Time.zone.name
    preference :weight_unit, :string, default: 'lb'
    preference :unit_system, :string, default: 'imperial'
    # email preferences
    preference :send_consumer_transactional_emails, :boolean, default: true
    # SMTP delivery channel (overrides app-wide ActionMailer config when set).
    preference :smtp_host, :string
    preference :smtp_port, :integer, default: 587
    preference :smtp_user, :string
    preference :smtp_password, :string
    preference :smtp_authentication, :string, default: 'plain'
    # Reply switch — when enabled, transactional emails carry a Reply-To header
    # pointing at customer_support_email and inbound replies are captured as
    # ContactMessage records; when disabled, no Reply-To is added and inbound
    # processing is skipped.
    preference :allow_email_replies, :boolean, default: false
    # Checkout preferences
    # Store-level fallback for the channel-owned `guest_checkout` preference
    # (see PallasTrade::Channel::Gating). Retained so existing accessors keep working.
    preference :guest_checkout, :boolean, default: true
    # Store-level fallback for the channel-owned `storefront_access` posture.
    preference :storefront_access, :string, default: 'public'
    # Canonical storefront origin used in customer-facing emails and links,
    # e.g. "https://myshop.com" — see #storefront_url for the fallback chain.
    preference :storefront_url, :string
    preference :special_instructions_enabled, :boolean, default: false
    preference :stock_reservation_ttl_minutes, :integer, default: 10
    # Address preferences
    preference :company_field_enabled, :boolean, default: false
    # digital assets preferences
    preference :limit_digital_download_count, :boolean, default: true
    preference :limit_digital_download_days, :boolean, default: true
    preference :digital_asset_authorized_clicks, :integer, default: 5
    preference :digital_asset_authorized_days, :integer, default: 7
    preference :digital_asset_link_expire_time, :integer, default: 300
    # Class name of the PallasTrade::OrderRouting::Strategy::Base subclass that
    # decides which StockLocation fulfills which items.
    preference :order_routing_strategy, :string, default: 'PallasTrade::OrderRouting::Strategy::Rules'

    #
    # Associations
    #
    has_many :carts, -> { incomplete }, class_name: 'PallasTrade::Order', inverse_of: :store
    has_many :checkouts, -> { incomplete }, class_name: 'PallasTrade::Order', inverse_of: :store
    has_many :orders, class_name: 'PallasTrade::Order'
    has_many :line_items, through: :orders, class_name: 'PallasTrade::LineItem'
    has_many :digital_links, through: :line_items, class_name: 'PallasTrade::DigitalLink'
    has_many :shipments, through: :orders, class_name: 'PallasTrade::Shipment'
    has_many :payments, through: :orders, class_name: 'PallasTrade::Payment'
    has_many :return_authorizations, through: :orders, class_name: 'PallasTrade::ReturnAuthorization'
    # has_many :reimbursements, through: :orders, class_name: 'PallasTrade::Reimbursement' FIXME: we should fetch this via Customer Return

    # :nullify (not :destroy) — clearing the collection must not cascade into
    # Promotion#not_used? / payment records; orphaned rows are detached, not deleted.
    has_many :payment_methods, class_name: 'PallasTrade::PaymentMethod', dependent: :nullify

    has_many :products, class_name: 'PallasTrade::Product', dependent: :nullify
    has_many :product_publications, through: :channels, source: :publications, class_name: 'PallasTrade::ProductPublication'
    has_many :variants, through: :products, class_name: 'PallasTrade::Variant', source: :variants_including_master
    has_many :stock_items, through: :variants, class_name: 'PallasTrade::StockItem'
    has_many :prices, through: :variants, class_name: 'PallasTrade::Price'
    has_many :price_lists, class_name: 'PallasTrade::PriceList', inverse_of: :store
    has_many :inventory_units, through: :variants, class_name: 'PallasTrade::InventoryUnit'
    has_many :option_value_variants, through: :variants, class_name: 'PallasTrade::OptionValueVariant'
    has_many :customer_returns, class_name: 'PallasTrade::CustomerReturn', inverse_of: :store

    has_many :store_credits, class_name: 'PallasTrade::StoreCredit'
    has_many :store_credit_events, through: :store_credits, class_name: 'PallasTrade::StoreCreditEvent'

    has_many :taxonomies, class_name: 'PallasTrade::Taxonomy'
    has_many :taxons, class_name: 'PallasTrade::Taxon'
    has_many :categories, class_name: 'PallasTrade::Category'

    has_many :promotions, class_name: 'PallasTrade::Promotion', dependent: :nullify

    has_many :wishlists, class_name: 'PallasTrade::Wishlist'

    has_many :data_feeds, class_name: 'PallasTrade::DataFeed'

    belongs_to :default_country, class_name: 'PallasTrade::Country'
    belongs_to :checkout_zone, class_name: 'PallasTrade::Zone'

    has_many :reports, class_name: 'PallasTrade::Report'
    has_many :exports, class_name: 'PallasTrade::Export'

    has_many :ai_providers, class_name: 'PallasTrade::AI::Provider'

    has_many :gift_cards, class_name: 'PallasTrade::GiftCard', dependent: :destroy

    has_many :policies, class_name: 'PallasTrade::Policy', dependent: :destroy, as: :owner

    has_many :posts, class_name: 'PallasTrade::Post', dependent: :destroy, inverse_of: :store

    has_many :webhook_endpoints, class_name: 'PallasTrade::WebhookEndpoint', dependent: :destroy, inverse_of: :store
    has_many :webhook_deliveries, through: :webhook_endpoints, class_name: 'PallasTrade::WebhookDelivery'

    has_many :channels, class_name: 'PallasTrade::Channel', dependent: :destroy
    has_many :order_routing_rules, through: :channels, class_name: 'PallasTrade::OrderRoutingRule'

    has_many :customer_groups, class_name: 'PallasTrade::CustomerGroup', dependent: :destroy, inverse_of: :store

    has_many :api_keys, class_name: 'PallasTrade::ApiKey', dependent: :destroy
    has_many :allowed_origins, class_name: 'PallasTrade::AllowedOrigin', dependent: :destroy
    has_many :redirects, class_name: 'PallasTrade::Redirect', dependent: :destroy, inverse_of: :store
    has_many :back_in_stock_subscriptions, class_name: 'PallasTrade::BackInStockSubscription', dependent: :destroy, inverse_of: :store
    has_many :abandoned_cart_notifications, class_name: 'PallasTrade::AbandonedCartNotification', dependent: :destroy, inverse_of: :store
    has_many :reviews, class_name: 'PallasTrade::Review', dependent: :destroy, inverse_of: :store
    has_many :email_templates, class_name: 'PallasTrade::EmailTemplate', dependent: :destroy, inverse_of: :store
    has_many :email_logs, class_name: 'PallasTrade::EmailLog', dependent: :destroy, inverse_of: :store
    has_many :contact_messages, class_name: 'PallasTrade::ContactMessage', dependent: :destroy, inverse_of: :store

    #
    # Validations
    #
    with_options presence: true do
      validates :name, :url, :mail_from_address, :code
    end
    validates :preferred_digital_asset_authorized_clicks, numericality: { only_integer: true, greater_than: 0 }
    validates :preferred_digital_asset_authorized_days, numericality: { only_integer: true, greater_than: 0 }
    validates :preferred_stock_reservation_ttl_minutes, numericality: { only_integer: true, greater_than: 0 }
    validates :preferred_storefront_access, inclusion: { in: PallasTrade::Channel::Gating::STOREFRONT_ACCESS }
    validate :preferred_storefront_url_is_an_origin
    validates :mail_from_address, email: { allow_blank: false }
    validates :customer_support_email, email: { allow_blank: true }
    # FIXME: we should remove this condition in v5
    if !ENV['pallastrade_DISABLE_DB_CONNECTION'] &&
       connected? &&
       table_exists? &&
       connection.column_exists?(:pallastrade_stores, :new_order_notifications_email)
      validates :new_order_notifications_email, email: { allow_blank: true }
    end
    validates :mailer_logo, content_type: Rails.application.config.active_storage.web_image_content_types

    #
    # Attachments
    #
    has_one_attached :logo, service: PallasTrade.public_storage_service_name
    has_one_attached :mailer_logo, service: PallasTrade.public_storage_service_name

    #
    # Callbacks
    before_validation :set_default_code, on: :create
    before_validation :normalize_preferred_storefront_url
    before_save :ensure_default_exists_and_is_unique
    after_create :create_default_policies

    #
    # Scopes
    #
    default_scope { order(created_at: :asc) }

    #
    # Delegations
    #

    def self.current(_url = nil)
      PallasTrade::Current.store
    end

    # @deprecated The or_initialize behavior will be removed in PallasTrade 5.5.
    def self.default
      # workaround for Mobility bug with first_or_initialize
      if where(default: true).any?
        where(default: true).first
      else
        PallasTrade::Deprecation.warn(
          'PallasTrade::Store.default returning a new unpersisted store when no default store exists is deprecated ' \
          'and will be removed in PallasTrade 6.0. Please ensure a default store is created before calling Store.default.'
        )
        new(default: true)
      end
    end

    def self.available_locales
      PallasTrade::Store.default&.supported_locales_list || []
    end

    # Resolves the store's default channel via the +default+ boolean column
    # so promoting another channel in the admin takes effect immediately.
    # Falls back to the first active channel only for malformed data with no
    # flagged default.
    # @return [PallasTrade::Channel, nil]
    def default_channel
      channels.default.first || channels.active.first
    end

    # @deprecated Use Markets instead. Will be removed in PallasTrade 5.5.
    def checkout_zone
      PallasTrade::Deprecation.warn('Store#checkout_zone is deprecated and will be removed in PallasTrade 5.5. Use Markets instead.')
      super
    end

    # @deprecated Use Markets instead. Will be removed in PallasTrade 5.5.
    def checkout_zone=(zone)
      PallasTrade::Deprecation.warn('Store#checkout_zone= is deprecated and will be removed in PallasTrade 5.5. Use Markets instead.')
      super
    end

    # Virtual attribute — sets the country for the default market created on store creation.
    # Not persisted on the store itself; only used by the after_create callback.
    attr_reader :default_country_iso

    def default_country_iso=(iso)
      return if iso.blank?

      @default_country_iso = iso

      country = PallasTrade::Country.by_iso(iso)

      unless country
        iso_country = ::Country[iso]
        return unless iso_country

        country = PallasTrade::Country.create!(
          iso_name: iso_country.local_name&.upcase,
          iso: iso_country.alpha2,
          iso3: iso_country.alpha3,
          name: iso_country.local_name,
          numcode: iso_country.number,
          states_required: PallasTrade::Address::STATES_REQUIRED.include?(iso),
          zipcode_required: !PallasTrade::Address::NO_ZIPCODE_ISO_CODES.include?(iso)
        )
      end

      @default_country_for_market = country
    end

    def unique_name
      @unique_name ||= "#{name} (#{code})"
    end

    def formatted_url
      @formatted_url ||= begin
        clean_url = url.to_s.sub(%r{^https?://}, '').split(':').first

        if Rails.env.development? || Rails.env.test?
          scheme = Rails.application.routes.default_url_options[:protocol] || :http
          port = Rails.application.routes.default_url_options[:port].presence || (Rails.env.development? ? 3000 : nil)

          if scheme.to_sym == :https
            URI::HTTPS.build(
              host: clean_url,
              port: port
            ).to_s
          else
            URI::HTTP.build(
              host: clean_url,
              port: port
            ).to_s
          end
        else
          URI::HTTPS.build(
            host: clean_url
          ).to_s
        end
      end
    end

    def url_or_custom_domain
      url
    end

    def formatted_url_or_custom_domain
      formatted_url
    end

    # Returns the storefront origin URL for use in customer-facing emails and links.
    # Uses the `storefront_url` preference when set, then the oldest non-loopback
    # allowed origin (the `http://localhost` origin seeded on install must never
    # leak into customer emails), otherwise falls back to formatted_url.
    #
    # @return [String] e.g. "https://myshop.com"
    def storefront_url
      preferred_storefront_url.presence ||
        allowed_origins.order(:created_at).reject(&:loopback?).first&.origin ||
        formatted_url
    end

    # Returns true if the given URL's origin matches one of the store's allowed origins.
    # See {PallasTrade::AllowedOrigin#matches?} for the matching rules (scheme/host/port).
    #
    # @param url [String] the full URL to check
    # @return [Boolean]
    def allowed_origin?(url)
      return false if url.blank?

      allowed_origins.any? { |allowed_origin| allowed_origin.matches?(url) }
    end

    # Returns the states available for checkout for the store
    # @param country [PallasTrade::Country] the country to get the states for
    # @return [Array<PallasTrade::State>]
    def states_available_for_checkout(country)
      country.states.to_a
    end

    # @deprecated Use {PallasTrade::Zone.all} or {#countries_with_shipping_coverage} instead.
    #   Will be removed in PallasTrade 5.5.
    def supported_shipping_zones
      PallasTrade::Deprecation.warn(
        'Store#supported_shipping_zones is deprecated and will be removed in PallasTrade 5.5. ' \
        'Use PallasTrade::Zone.all or Store#countries_with_shipping_coverage instead.'
      )
      zone = PallasTrade::Zone.find_by(id: read_attribute(:checkout_zone_id))
      if zone.present?
        [zone]
      else
        PallasTrade::Zone.includes(zone_members: :zoneable).all
      end
    end

    # Returns countries covered by at least one shipping zone
    # that has an active shipping method attached.
    # Handles both country-type zones (direct membership) and
    # state-type zones (country inferred from state).
    #
    # @return [ActiveRecord::Relation<PallasTrade::Country>]
    def countries_with_shipping_coverage
      zone_ids = PallasTrade::Zone
                 .joins(:shipping_methods)
                 .select(:id)

      country_zone_country_ids = PallasTrade::ZoneMember
                                 .where(zone_id: zone_ids, zoneable_type: 'PallasTrade::Country')
                                 .select(:zoneable_id)

      state_zone_country_ids = PallasTrade::State
                               .where(id: PallasTrade::ZoneMember
                                          .where(zone_id: zone_ids, zoneable_type: 'PallasTrade::State')
                                          .select(:zoneable_id))
                               .select(:country_id)

      PallasTrade::Country
        .where(id: country_zone_country_ids)
        .or(PallasTrade::Country.where(id: state_zone_country_ids))
        .order(:name)
    end

    # Returns the default stock location for the store or creates a new one if it doesn't exist
    # @return [PallasTrade::StockLocation]
    def default_stock_location
      @default_stock_location ||= begin
        stock_location_scope = PallasTrade::StockLocation.where(default: true)
        stock_location_scope.first || ActiveRecord::Base.connected_to(role: :writing) do
          stock_location_scope.create(default: true, name: PallasTrade.t(:default_stock_location_name),
                                      country: default_country)
        end
      end
    end

    def admin_users
      PallasTrade::Deprecation.warn('Store#admin_users is deprecated and will be removed in PallasTrade 5.5. Please use Store#users instead.')

      users
    end

    def metric_unit_system?
      preferred_unit_system == 'metric'
    end

    def default_shipping_category
      @default_shipping_category ||= ShippingCategory.find_or_create_by(name: 'Default')
    end

    def digital_shipping_category
      @digital_shipping_category ||= ShippingCategory.find_or_create_by(name: 'Digital')
    end

    private

    def create_default_policies
      PallasTrade::Events.disable do
        [
          translate_with_store_locale_fallback('pallastrade.terms_of_service'),
          translate_with_store_locale_fallback('pallastrade.privacy_policy'),
          translate_with_store_locale_fallback('pallastrade.returns_policy'),
          translate_with_store_locale_fallback('pallastrade.shipping_policy')
        ].each do |policy_name|
          # Manual exists?/create to work around Mobility bug with find_or_create_by
          next if policies.with_matching_name(policy_name).exists?

          policies.create(name: policy_name)
        end
      end
    end

    # Translates a key using the store's default locale with fallback to :en
    def translate_with_store_locale_fallback(key)
      locale = default_locale.presence&.to_sym || :en
      I18n.t(key, locale: locale, default: I18n.t(key, locale: :en))
    end

    def ensure_default_exists_and_is_unique
      if default
        PallasTrade::Store.where.not(id: id).update_all(default: false)
      elsif PallasTrade::Store.where(default: true).count.zero?
        self.default = true
      end
    end

    def should_generate_new_friendly_id?
      false
    end

    def set_default_code
      self.code = 'default' if code.blank?
    end

    # The storefront URL preference must always hold a canonical origin — it
    # becomes the base for customer-email links and completes the storefront
    # setup task, and the v3 Admin API writes it without any controller-side
    # normalization. Parseable input is canonicalized here; garbage is left
    # in place for the validation below to reject.
    def normalize_preferred_storefront_url
      raw = preferred_storefront_url
      return if raw.blank?

      normalized = PallasTrade::AllowedOrigin.normalize_origin(raw)
      self.preferred_storefront_url = normalized if normalized
    end

    def preferred_storefront_url_is_an_origin
      raw = preferred_storefront_url
      return if raw.blank?
      return if PallasTrade::AllowedOrigin.normalize_origin(raw)

      errors.add(:preferred_storefront_url, :invalid)
    end
  end
end
