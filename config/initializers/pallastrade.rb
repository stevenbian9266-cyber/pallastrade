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
  # Disable startup warning about missing engine migrations.
  # The PallasTrade gems manage their own migration paths — the app
  # does not need (and should not keep) copies in db/migrate.
  config.disable_migration_check = true

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
  PallasTrade.permissions.assign(:default, [PallasTrade::PermissionSets::DefaultCustomer])
  PallasTrade.permissions.assign(:admin, [PallasTrade::PermissionSets::SuperUser])
end

Rails.application.config.to_prepare do
  require_dependency 'pallastrade/authentication_helpers'
end

Devise.parent_controller = 'PallasTrade::BaseController' if defined?(Devise) && Devise.respond_to?(:parent_controller)
