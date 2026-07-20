# Uncomment lines below to add your own custom business logic
# such as promotions, shipping methods, etc.
Rails.application.config.after_initialize do
  # Rails.application.config.PallasTrade.shipping_methods << PallasTrade::ShippingMethods::SuperExpensiveNotVeryFastShipping
  Rails.application.config.pallastrade.payment_methods << SpreeAdyen::Gateway

  # Rails.application.config.PallasTrade.calculators.tax_rates << PallasTrade::TaxRates::FinanceTeamForcedMeToCodeThis

  # Rails.application.config.PallasTrade.stock_splitters << PallasTrade::Stock::Splitters::SecretLogicSplitter

  # Rails.application.config.PallasTrade.adjusters << PallasTrade::Adjustable::Adjuster::TaxTheRich

  # Custom promotions
  # Rails.application.config.PallasTrade.calculators.promotion_actions_create_adjustments << PallasTrade::Calculators::PromotionActions::CreateAdjustments::AddDiscountForFriends
  # Rails.application.config.PallasTrade.calculators.promotion_actions_create_item_adjustments << PallasTrade::Calculators::PromotionActions::CreateItemAdjustments::FinanceTeamForcedMeToCodeThis
  # Rails.application.config.PallasTrade.promotions.rules << PallasTrade::Promotions::Rules::OnlyForVIPCustomers
  # Rails.application.config.PallasTrade.promotions.actions << PallasTrade::Promotions::Actions::GiftWithPurchase

  # Rails.application.config.PallasTrade.taxon_rules << PallasTrade::TaxonRules::ProductsWithColor

  # Rails.application.config.PallasTrade.exports << PallasTrade::Exports::Payments
  # Rails.application.config.PallasTrade.reports << PallasTrade::Reports::MassivelyOvercomplexReportForCfo

  # Themes and page builder
  # Rails.application.config.PallasTrade.themes << PallasTrade::Themes::NewShinyTheme
  # Rails.application.config.PallasTrade.theme_layout_sections << PallasTrade::PageSections::SuperImportantCeoBio
  # Rails.application.config.PallasTrade.page_sections << PallasTrade::PageSections::ContactFormToGetInTouch
  # Rails.application.config.PallasTrade.page_blocks << PallasTrade::PageBlocks::BigRedButtonToCallSales

  # Storefront partials
  if Rails.application.config.respond_to?(:PALLASTRADE_storefront)
    Rails.application.config.PALLASTRADE_storefront.head_partials << 'pallastrade_adyen/head'
  end
end
