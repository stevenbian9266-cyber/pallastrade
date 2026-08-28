# frozen_string_literal: true

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
# More on configuring PallasTrade preferences can be found in the project documentation.

PallasTrade::Config.show_products_without_price = true

# PallasTrade base and user classes
PallasTrade.base_class = 'PallasTrade::Base'
PallasTrade.user_class = 'PallasTrade::User'
PallasTrade.admin_user_class = 'PallasTrade::AdminUser'

PallasTrade.config do |config|
  # The application commits the branded engine migrations in db/migrate.
  # Disable the copy-check because those versions are already tracked here.
  config.disable_migration_check = true

  # Order lifecycle P5 (2026-08-27): 自动拆单策略列表默认关闭（store.preferred_auto_split_orders 覆盖）
  config.auto_split_orders = []

  # Order lifecycle P6 (2026-08-28): Admin 手动拆单默认关闭（store.preferred_manual_split_enabled 覆盖）
  config.admin_manual_split_enabled = false

  # Example:
  # Uncomment to stop tracking inventory levels in the application
  # config.track_inventory_levels = false
end

# Configure PallasTrade Dependencies
#
# Note: If a dependency is set here it will NOT be stored within the cache & database upon initialization.
#       Just removing an entry from this initializer will make the dependency value go away.
#
# More on how to use PallasTrade dependencies can be found in the project documentation.
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

  # Required authorization baseline for the storefront and admin panel.
  # PALLAS-CUSTOM (2026-08-16 权限体系重构): admin 角色权限已由 DB 驱动
  # （PallasTrade::RolePermission，见 Seeds::Roles 的 SuperUser seed），
  # 不再在代码中 assign；此处仅保留 storefront default 客户基线。
  PallasTrade.permissions.assign(:default, [PallasTrade::PermissionSets::DefaultCustomer])
end

# Serve Active Storage URLs from the configured CDN host when present.
PallasTrade.cdn_host = ENV['CDN_HOST'] if ENV['CDN_HOST'].present?

# Background job queues are part of the public operational contract.
PallasTrade.queues.default = :default
PallasTrade.queues.events = :pallastrade_events
PallasTrade.queues.exports = :pallastrade_exports
PallasTrade.queues.images = :pallastrade_images
PallasTrade.queues.imports = :pallastrade_imports
PallasTrade.queues.products = :pallastrade_products
PallasTrade.queues.reports = :pallastrade_reports
PallasTrade.queues.variants = :pallastrade_variants
PallasTrade.queues.taxons = :pallastrade_taxons
PallasTrade.queues.stock_location_stock_items = :pallastrade_stock_location_stock_items
PallasTrade.queues.coupon_codes = :pallastrade_coupon_codes
PallasTrade.queues.addresses = :pallastrade_addresses
PallasTrade.queues.gift_cards = :pallastrade_gift_cards
PallasTrade.queues.webhooks = :pallastrade_webhooks
PallasTrade.queues.payment_webhooks = :pallastrade_payment_webhooks
PallasTrade.queues.api_keys = :pallastrade_api_keys
PallasTrade.queues.search = :pallastrade_search

# Request specs use the deterministic database provider. Development and
# production opt in to Meilisearch by configuring its URL.
if !Rails.env.test? && ENV['MEILISEARCH_URL'].present?
  PallasTrade.search_provider = 'PallasTrade::SearchProvider::Meilisearch'
end
Rails.application.config.to_prepare do
  require_dependency 'pallastrade/authentication_helpers'
end

Devise.parent_controller = 'PallasTrade::BaseController' if defined?(Devise) && Devise.respond_to?(:parent_controller)
