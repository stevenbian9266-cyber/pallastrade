# Configure PallasTrade Preferences
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
# More on configuring PallasTrade preferences can be found at:
# https://pallastrade.cn/docs/developer/customization
PallasTrade.config do |config|
  # Example:
  # Uncomment to stop tracking inventory levels in the application
  # config.track_inventory_levels = false
end

# Background job queue names
# PallasTrade.queues.default = :default
# PallasTrade.queues.events = :default  # Event subscribers (PallasTrade::Events::SubscriberJob)
# PallasTrade.queues.variants = :default
# PallasTrade.queues.stock_location_stock_items = :default
# PallasTrade.queues.coupon_codes = :default

# Use a CDN host for images, eg. Cloudfront
# This is used in the frontend to generate absolute URLs to images
# Default is nil and your application host will be used
# PallasTrade.cdn_host = 'cdn.example.com'

# Multi-store setup
# You need to set a wildcard `root_domain` on the store to enable multi-store setup
# all new stores will be created in a subdomain of the root domain, eg. store1.lvh.me, store2.lvh.me, etc.
# PallasTrade.root_domain = ENV.fetch('pallastrade_ROOT_DOMAIN', 'lvh.me')

# Use a different service for storage (S3, google, etc)
# unless Rails.env.test?
#   PallasTrade.private_storage_service_name = :amazon_public # public assets, such as product images
#   PallasTrade.public_storage_service_name = :amazon_private # private assets, such as invoices, etc
# end

# Configure PallasTrade Dependencies
#
# Note: If a dependency is set here it will NOT be stored within the cache & database upon initialization.
#       Just removing an entry from this initializer will make the dependency value go away.
#
# More on how to use PallasTrade dependencies can be found at:
# https://pallastrade.cn/docs/customization/dependencies
PallasTrade.dependencies do |dependencies|
  # Example:
  # Uncomment to change the default Service handling adding Items to Cart
  # dependencies.cart_add_item_service = 'MyNewAwesomeService'
end

# PallasTrade::Api::Dependencies.storefront_cart_serializer = 'MyRailsApp::CartSerializer'

# uncomment lines below to add your own custom business logic
# such as promotions, shipping methods, etc
Rails.application.config.after_initialize do
  # Payment methods and shipping calculators
  # PallasTrade.payment_methods << PallasTrade::PaymentMethods::VerySafeAndReliablePaymentMethod
  # PallasTrade.calculators.shipping_methods << PallasTrade::ShippingMethods::SuperExpensiveNotVeryFastShipping
  # PallasTrade.calculators.tax_rates << PallasTrade::TaxRates::FinanceTeamForcedMeToCodeThis

  # Stock splitters and adjusters
  # PallasTrade.stock_splitters << PallasTrade::Stock::Splitters::SecretLogicSplitter
  # PallasTrade.adjusters << PallasTrade::Adjustable::Adjuster::TaxTheRich

  # Custom promotions
  # PallasTrade.calculators.promotion_actions_create_adjustments << PallasTrade::Calculators::PromotionActions::CreateAdjustments::AddDiscountForFriends
  # PallasTrade.calculators.promotion_actions_create_item_adjustments << PallasTrade::Calculators::PromotionActions::CreateItemAdjustments::FinanceTeamForcedMeToCodeThis
  # PallasTrade.promotions.rules << PallasTrade::Promotions::Rules::OnlyForVIPCustomers
  # PallasTrade.promotions.actions << PallasTrade::Promotions::Actions::GiftWithPurchase

  # Taxon rules
  # PallasTrade.taxon_rules << PallasTrade::TaxonRules::ProductsWithColor

  # Exports and reports
  # PallasTrade.export_types << PallasTrade::Exports::Payments
  # PallasTrade.reports << PallasTrade::Reports::MassivelyOvercomplexReportForCfo

  # Admin partials
  # PallasTrade.admin.partials.product_form << 'pallastrade/admin/products/custom_section'

  # Role-based permissions
  # Configure which permission sets are assigned to each role
  # More on permission sets: https://pallastrade.cn/docs/developer/customization/permissions
  PallasTrade.permissions.assign(:default, [PallasTrade::PermissionSets::DefaultCustomer])
  PallasTrade.permissions.assign(:admin, [PallasTrade::PermissionSets::SuperUser])

  # Example: Create a custom role with specific permissions
  # PallasTrade.permissions.assign(:customer_service, [
  #   PallasTrade::PermissionSets::DashboardDisplay,
  #   PallasTrade::PermissionSets::OrderManagement,
  #   PallasTrade::PermissionSets::UserDisplay
  # ])
  #
  # Available permission sets:
  # - PallasTrade::PermissionSets::SuperUser (full admin access)
  # - PallasTrade::PermissionSets::DefaultCustomer (storefront access)
  # - PallasTrade::PermissionSets::DashboardDisplay (view admin dashboard)
  # - PallasTrade::PermissionSets::OrderDisplay / OrderManagement
  # - PallasTrade::PermissionSets::ProductDisplay / ProductManagement
  # - PallasTrade::PermissionSets::UserDisplay / UserManagement
  # - PallasTrade::PermissionSets::StockDisplay / StockManagement
  # - PallasTrade::PermissionSets::PromotionManagement
  # - PallasTrade::PermissionSets::ConfigurationManagement
  # - PallasTrade::PermissionSets::RoleManagement
end

# Background job queue configuration
# PallasTrade.queues.default = :default
# PallasTrade.queues.events = :default
# PallasTrade.queues.exports = :default
# PallasTrade.queues.images = :default
# PallasTrade.queues.imports = :default
# PallasTrade.queues.products = :default
# PallasTrade.queues.reports = :default
# PallasTrade.queues.variants = :default
# PallasTrade.queues.taxons = :default
# PallasTrade.queues.stock_location_stock_items = :default
# PallasTrade.queues.coupon_codes = :default
# PallasTrade.queues.themes = :default
# PallasTrade.queues.addresses = :default
# PallasTrade.queues.gift_cards = :default
# PallasTrade.queues.webhooks = :default
# PallasTrade.queues.payment_webhooks = :default
# PallasTrade.queues.api_keys = :default
# PallasTrade.queues.search = :default

# Search provider
# PallasTrade.search_provider = 'PallasTrade::SearchProvider::Meilisearch'

PallasTrade.user_class = <%= (options[:user_class].blank? ? 'PallasTrade::LegacyUser' : options[:user_class]).inspect %>
PallasTrade.admin_user_class = <%= (options[:admin_user_class].blank? ? (options[:user_class].blank? ? 'PallasTrade::LegacyAdminUser' : options[:user_class]) : options[:admin_user_class]).inspect %>
