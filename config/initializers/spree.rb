# frozen_string_literal: true

# Configure Spree Preferences
#
# Note: Initializing preferences available within the Admin will overwrite any changes that were made through the user interface when you restart.
#       If you would like users to be able to update a setting with the Admin it should NOT be set here.
#
# Note: If a preference is set here it will be stored within the cache & database upon initialization.
#       Just removing an entry from this initializer will not make the preference value go away.
#       Instead you must either set a new value or remove entry, clear cache, and remove database entry.
#
# In order to initialize a setting do:
# config.setting_name = 'new value'
#
# More on configuring Spree preferences can be found at:
# https://docs.spreecommerce.org/developer/customization
PallasTrade.config do |config|
  # Example:
  # Uncomment to stop tracking inventory levels in the application
  # config.track_inventory_levels = false
end

# Configure Spree Dependencies
#
# Note: If a dependency is set here it will NOT be stored within the cache & database upon initialization.
#       Just removing an entry from this initializer will make the dependency value go away.
#
# More on how to use Spree dependencies can be found at:
# https://docs.spreecommerce.org/customization/dependencies
PallasTrade.dependencies do |dependencies|
  # Example:
  # Uncomment to change the default Service handling adding Items to Cart
  # dependencies.cart_add_item_service = 'MyNewAwesomeService'
end

Rails.application.config.after_initialize do
  # PallasTrade.shipping_methods << PallasTrade::ShippingMethods::SuperExpensiveNotVeryFastShipping
  # PallasTrade.payment_methods << PallasTrade::PaymentMethods::VerySafeAndReliablePaymentMethod

  # PallasTrade.calculators.tax_rates << PallasTrade::TaxRates::FinanceTeamForcedMeToCodeThis

  # PallasTrade.stock_splitters << PallasTrade::Stock::Splitters::SecretLogicSplitter

  # PallasTrade.adjusters << PallasTrade::Adjustable::Adjuster::TaxTheRich

  # Custom promotions
  # PallasTrade.calculators.promotion_actions_create_adjustments << PallasTrade::Calculators::PromotionActions::CreateAdjustments::AddDiscountForFriends
  # PallasTrade.calculators.promotion_actions_create_item_adjustments << PallasTrade::Calculators::PromotionActions::CreateItemAdjustments::FinanceTeamForcedMeToCodeThis
  # PallasTrade.promotions.rules << PallasTrade::Promotions::Rules::OnlyForVIPCustomers
  # PallasTrade.promotions.actions << PallasTrade::Promotions::Actions::GiftWithPurchase

  # PallasTrade.taxon_rules << PallasTrade::TaxonRules::ProductsWithColor

  # PallasTrade.exports << PallasTrade::Exports::Payments
  # PallasTrade.reports << PallasTrade::Reports::MassivelyOvercomplexReportForCfo

  # Role-based permissions
  PallasTrade.permissions.assign(:default, [PallasTrade::PermissionSets::DefaultCustomer])
  PallasTrade.permissions.assign(:admin, [PallasTrade::PermissionSets::SuperUser])
end

PallasTrade.user_class = 'PallasTrade::User'
PallasTrade.admin_user_class = 'PallasTrade::AdminUser'

# Serve Active Storage attachment URLs (product images, logos, etc.) from a CDN
# host instead of the application host. Host only, no protocol — the scheme
# comes from routes.default_url_options (see config/environments/production.rb).
PallasTrade.cdn_host = ENV['CDN_HOST'] if ENV['CDN_HOST'].present?

# Background job queue configuration
PallasTrade.queues.default = :default
PallasTrade.queues.events = :spree_events
PallasTrade.queues.exports = :spree_exports
PallasTrade.queues.images = :spree_images
PallasTrade.queues.imports = :spree_imports
PallasTrade.queues.products = :spree_products
PallasTrade.queues.reports = :spree_reports
PallasTrade.queues.variants = :spree_variants
PallasTrade.queues.taxons = :spree_taxons
PallasTrade.queues.stock_location_stock_items = :spree_stock_location_stock_items
PallasTrade.queues.coupon_codes = :spree_coupon_codes
PallasTrade.queues.addresses = :spree_addresses
PallasTrade.queues.gift_cards = :spree_gift_cards
PallasTrade.queues.webhooks = :spree_webhooks
PallasTrade.queues.payment_webhooks = :spree_payment_webhooks
PallasTrade.queues.api_keys = :spree_api_keys
PallasTrade.queues.search = :spree_search

# Search provider
if ENV['MEILISEARCH_URL'].present?
  PallasTrade.search_provider = 'PallasTrade::SearchProvider::Meilisearch'
end

Rails.application.config.to_prepare do
  require 'pallastrade/authentication_helpers'
end

Devise.parent_controller = 'PallasTrade::BaseController' if defined?(Devise) && Devise.respond_to?(:parent_controller)
