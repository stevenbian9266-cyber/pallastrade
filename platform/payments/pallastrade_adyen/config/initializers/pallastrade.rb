# Uncomment lines below to add your own custom business logic
# such as promotions, shipping methods, etc.
Rails.application.config.after_initialize do
  # Rails.application.config.pallastrade.shipping_methods << PallasTrade::ShippingMethods::SuperExpensiveNotVeryFastShipping
  Rails.application.config.pallastrade.payment_methods << PallasTradeAdyen::Gateway

  # Rails.application.config.pallastrade.calculators.tax_rates << PallasTrade::TaxRates::FinanceTeamForcedMeToCodeThis

  # Rails.application.config.pallastrade.stock_splitters << PallasTrade::Stock::Splitters::SecretLogicSplitter

  # Rails.application.config.pallastrade.adjusters << PallasTrade::Adjustable::Adjuster::TaxTheRich

  # Custom promotions
  # Rails.application.config.pallastrade.calculators.promotion_actions_create_adjustments << PallasTrade::Calculators::PromotionActions::CreateAdjustments::AddDiscountForFriends
  # Rails.application.config.pallastrade.calculators.promotion_actions_create_item_adjustments << PallasTrade::Calculators::PromotionActions::CreateItemAdjustments::FinanceTeamForcedMeToCodeThis
  # Rails.application.config.pallastrade.promotions.rules << PallasTrade::Promotions::Rules::OnlyForVIPCustomers
  # Rails.application.config.pallastrade.promotions.actions << PallasTrade::Promotions::Actions::GiftWithPurchase

  # Rails.application.config.pallastrade.taxon_rules << PallasTrade::TaxonRules::ProductsWithColor

  # Rails.application.config.pallastrade.exports << PallasTrade::Exports::Payments
  # Rails.application.config.pallastrade.reports << PallasTrade::Reports::MassivelyOvercomplexReportForCfo

  # Themes and page builder
  # Rails.application.config.pallastrade.themes << PallasTrade::Themes::NewShinyTheme
  # Rails.application.config.pallastrade.theme_layout_sections << PallasTrade::PageSections::SuperImportantCeoBio
  # Rails.application.config.pallastrade.page_sections << PallasTrade::PageSections::ContactFormToGetInTouch
  # Rails.application.config.pallastrade.page_blocks << PallasTrade::PageBlocks::BigRedButtonToCallSales

  # Storefront partials
  if Rails.application.config.respond_to?(:pallastrade_storefront)
    Rails.application.config.pallastrade_storefront.head_partials << 'pallastrade_adyen/head'
  end
end
