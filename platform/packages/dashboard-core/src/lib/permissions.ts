/**
 * CanCanCan subject class names — use these constants instead of raw strings
 * to avoid typos in permission checks.
 *
 * Matches the Ruby class names serialized by the /api/v3/admin/me endpoint.
 */
export const Subject = {
  All: 'all',
  Product: 'PallasTrade::Product',
  Variant: 'PallasTrade::Variant',
  Order: 'PallasTrade::Order',
  Customer: 'PallasTrade::User',
  CustomerGroup: 'PallasTrade::CustomerGroup',
  AdminUser: 'PallasTrade::AdminUser',
  ApiKey: 'PallasTrade::ApiKey',
  AllowedOrigin: 'PallasTrade::AllowedOrigin',
  Store: 'PallasTrade::Store',
  Channel: 'PallasTrade::Channel',
  // Categories are PallasTrade::Category < PallasTrade::Taxon; abilities are published under
  // the PallasTrade::Taxon subject, so the value stays 'PallasTrade::Taxon' while the key
  // reads as the user-facing resource name.
  Category: 'PallasTrade::Taxon',
  OptionType: 'PallasTrade::OptionType',
  OptionValue: 'PallasTrade::OptionValue',
  TaxCategory: 'PallasTrade::TaxCategory',
  CustomFieldDefinition: 'PallasTrade::MetafieldDefinition',
  PaymentMethod: 'PallasTrade::PaymentMethod',
  ShippingMethod: 'PallasTrade::ShippingMethod',
  StockLocation: 'PallasTrade::StockLocation',
  StockItem: 'PallasTrade::StockItem',
  StockTransfer: 'PallasTrade::StockTransfer',
  PriceList: 'PallasTrade::PriceList',
  PriceRule: 'PallasTrade::PriceRule',
  Promotion: 'PallasTrade::Promotion',
  PromotionAction: 'PallasTrade::PromotionAction',
  PromotionRule: 'PallasTrade::PromotionRule',
  GiftCard: 'PallasTrade::GiftCard',
  Market: 'PallasTrade::Market',
  WebhookEndpoint: 'PallasTrade::WebhookEndpoint',
  WebhookDelivery: 'PallasTrade::WebhookDelivery',
  Wishlist: 'PallasTrade::Wishlist',
} as const

export type SubjectName = (typeof Subject)[keyof typeof Subject] | string

/** CanCanCan standard actions */
export const Action = {
  Manage: 'manage',
  Read: 'read',
  Create: 'create',
  Update: 'update',
  Destroy: 'destroy',
} as const

export type ActionName = (typeof Action)[keyof typeof Action] | string
