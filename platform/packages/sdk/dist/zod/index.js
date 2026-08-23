import { z } from 'zod';

// src/zod/generated/Address.ts
var AddressSchema = z.object({
  id: z.string(),
  first_name: z.string().nullable(),
  last_name: z.string().nullable(),
  full_name: z.string(),
  address1: z.string().nullable(),
  address2: z.string().nullable(),
  postal_code: z.string().nullable(),
  city: z.string().nullable(),
  phone: z.string().nullable(),
  company: z.string().nullable(),
  country_name: z.string(),
  country_iso: z.string(),
  state_text: z.string().nullable(),
  state_abbr: z.string().nullable(),
  quick_checkout: z.boolean(),
  is_default_billing: z.boolean(),
  is_default_shipping: z.boolean(),
  state_name: z.string().nullable()
});
var BaseSchema = z.object({
  id: z.string()
});
var DiscountSchema = z.object({
  id: z.string(),
  promotion_id: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  code: z.string().nullable(),
  amount: z.string().nullable(),
  display_amount: z.string().nullable()
});
var DeliveryMethodSchema = z.object({
  id: z.string(),
  name: z.string(),
  code: z.string().nullable()
});
var DeliveryRateSchema = z.object({
  id: z.string(),
  delivery_method_id: z.string(),
  name: z.string(),
  selected: z.boolean(),
  cost: z.string(),
  total: z.string(),
  additional_tax_total: z.string(),
  included_tax_total: z.string(),
  tax_total: z.string(),
  display_cost: z.string(),
  display_total: z.string(),
  display_additional_tax_total: z.string(),
  display_included_tax_total: z.string(),
  display_tax_total: z.string(),
  delivery_method: DeliveryMethodSchema
});
var StockLocationSchema = z.object({
  id: z.string(),
  state_abbr: z.string().nullable(),
  name: z.string(),
  address1: z.string().nullable(),
  city: z.string().nullable(),
  zipcode: z.string().nullable(),
  country_iso: z.string().nullable(),
  country_name: z.string().nullable(),
  state_text: z.string().nullable()
});

// src/zod/generated/Fulfillment.ts
var FulfillmentSchema = z.object({
  id: z.string(),
  number: z.string(),
  tracking: z.string().nullable(),
  tracking_url: z.string().nullable(),
  cost: z.string().nullable(),
  display_cost: z.string().nullable(),
  total: z.string().nullable(),
  display_total: z.string().nullable(),
  discount_total: z.string().nullable(),
  display_discount_total: z.string().nullable(),
  additional_tax_total: z.string().nullable(),
  display_additional_tax_total: z.string().nullable(),
  included_tax_total: z.string().nullable(),
  display_included_tax_total: z.string().nullable(),
  tax_total: z.string().nullable(),
  display_tax_total: z.string().nullable(),
  status: z.string(),
  fulfillment_type: z.string(),
  fulfilled_at: z.string().nullable(),
  items: z.array(z.object({ item_id: z.any() })),
  delivery_method: DeliveryMethodSchema,
  stock_location: StockLocationSchema,
  delivery_rates: z.array(DeliveryRateSchema)
});
var GiftCardSchema = z.object({
  id: z.string(),
  code: z.string(),
  status: z.string(),
  currency: z.string(),
  amount: z.string().nullable(),
  amount_used: z.string().nullable(),
  amount_authorized: z.string().nullable(),
  amount_remaining: z.string().nullable(),
  display_amount: z.string().nullable(),
  display_amount_used: z.string().nullable(),
  display_amount_remaining: z.string().nullable(),
  expires_at: z.string().nullable(),
  redeemed_at: z.string().nullable(),
  expired: z.boolean(),
  active: z.boolean()
});
var DigitalLinkSchema = z.object({
  id: z.string(),
  access_counter: z.number(),
  filename: z.string(),
  content_type: z.string(),
  download_url: z.string(),
  authorizable: z.boolean(),
  expired: z.boolean(),
  access_limit_exceeded: z.boolean()
});
var OptionValueSchema = z.object({
  id: z.string(),
  option_type_id: z.string(),
  name: z.string(),
  label: z.string(),
  position: z.number(),
  color_code: z.string().nullable(),
  option_type_name: z.string(),
  option_type_label: z.string(),
  image_url: z.string().nullable()
});

// src/zod/generated/LineItem.ts
var LineItemSchema = z.object({
  id: z.string(),
  variant_id: z.string(),
  preorder: z.boolean(),
  preorder_ships_at: z.string().nullable(),
  quantity: z.number(),
  currency: z.string(),
  name: z.string(),
  slug: z.string(),
  options_text: z.string(),
  price: z.string().nullable(),
  display_price: z.string().nullable(),
  total: z.string().nullable(),
  display_total: z.string().nullable(),
  adjustment_total: z.string().nullable(),
  display_adjustment_total: z.string().nullable(),
  additional_tax_total: z.string().nullable(),
  display_additional_tax_total: z.string().nullable(),
  included_tax_total: z.string().nullable(),
  display_included_tax_total: z.string().nullable(),
  discount_total: z.string().nullable(),
  display_discount_total: z.string().nullable(),
  pre_tax_amount: z.string().nullable(),
  display_pre_tax_amount: z.string().nullable(),
  discounted_amount: z.string().nullable(),
  display_discounted_amount: z.string().nullable(),
  display_compare_at_amount: z.string().nullable(),
  compare_at_amount: z.string().nullable(),
  thumbnail_url: z.string().nullable(),
  option_values: z.array(OptionValueSchema),
  digital_links: z.array(DigitalLinkSchema)
});
var StateSchema = z.object({
  abbr: z.string(),
  name: z.string()
});

// src/zod/generated/Country.ts
var CountrySchema = z.object({
  iso: z.string(),
  iso3: z.string(),
  name: z.string(),
  states_required: z.boolean(),
  zipcode_required: z.boolean(),
  states: z.array(StateSchema).optional(),
  market: z.lazy(() => MarketSchema).nullable().optional()
});

// src/zod/generated/Market.ts
var MarketSchema = z.object({
  id: z.string(),
  name: z.string(),
  currency: z.string(),
  default_locale: z.string(),
  tax_inclusive: z.boolean(),
  default: z.boolean(),
  country_isos: z.array(z.string()),
  supported_locales: z.array(z.string()),
  countries: z.array(z.lazy(() => CountrySchema)).optional()
});
var PaymentMethodSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  type: z.string(),
  session_required: z.boolean(),
  source_required: z.boolean()
});

// src/zod/generated/Payment.ts
var PaymentSchema = z.object({
  id: z.string(),
  payment_method_id: z.string(),
  response_code: z.string().nullable(),
  number: z.string(),
  amount: z.string().nullable(),
  display_amount: z.string().nullable(),
  status: z.string(),
  source_type: z.string().nullable(),
  source_id: z.string().nullable(),
  source: z.any(),
  payment_method: PaymentMethodSchema
});

// src/zod/generated/Cart.ts
var CartSchema = z.object({
  id: z.string(),
  market_id: z.string().nullable(),
  number: z.string(),
  token: z.string(),
  email: z.string().nullable(),
  customer_note: z.string().nullable(),
  currency: z.string(),
  locale: z.string().nullable(),
  total_quantity: z.number(),
  warnings: z.array(z.any()),
  item_total: z.string().nullable(),
  display_item_total: z.string().nullable(),
  adjustment_total: z.string().nullable(),
  display_adjustment_total: z.string().nullable(),
  discount_total: z.string().nullable(),
  display_discount_total: z.string().nullable(),
  tax_total: z.string().nullable(),
  display_tax_total: z.string().nullable(),
  included_tax_total: z.string().nullable(),
  display_included_tax_total: z.string().nullable(),
  additional_tax_total: z.string().nullable(),
  display_additional_tax_total: z.string().nullable(),
  total: z.string().nullable(),
  display_total: z.string().nullable(),
  gift_card_total: z.string().nullable(),
  display_gift_card_total: z.string().nullable(),
  amount_due: z.string().nullable(),
  display_amount_due: z.string().nullable(),
  delivery_total: z.string().nullable(),
  display_delivery_total: z.string().nullable(),
  store_credit_total: z.string().nullable(),
  display_store_credit_total: z.string().nullable(),
  covered_by_store_credit: z.boolean(),
  current_step: z.string(),
  completed_steps: z.array(z.string()),
  requirements: z.array(z.object({ step: z.string(), field: z.string(), message: z.string() })),
  shipping_eq_billing_address: z.boolean(),
  discounts: z.array(DiscountSchema),
  items: z.array(LineItemSchema),
  fulfillments: z.array(FulfillmentSchema),
  payments: z.array(PaymentSchema),
  billing_address: AddressSchema.nullable(),
  shipping_address: AddressSchema.nullable(),
  payment_methods: z.array(PaymentMethodSchema),
  gift_card: GiftCardSchema.nullable(),
  market: z.lazy(() => MarketSchema).nullable()
});
var CustomFieldSchema = z.object({
  id: z.string(),
  label: z.string(),
  type: z.string(),
  field_type: z.string(),
  key: z.string(),
  value: z.any()
});

// src/zod/generated/Category.ts
var CategorySchema = z.object({
  id: z.string(),
  name: z.string(),
  permalink: z.string(),
  position: z.number(),
  depth: z.number(),
  meta_title: z.string().nullable(),
  meta_description: z.string().nullable(),
  meta_keywords: z.string().nullable(),
  children_count: z.number(),
  parent_id: z.string().nullable(),
  description: z.string(),
  description_html: z.string(),
  image_url: z.string().nullable(),
  square_image_url: z.string().nullable(),
  is_root: z.boolean(),
  is_child: z.boolean(),
  is_leaf: z.boolean(),
  parent: z.lazy(() => CategorySchema).optional(),
  children: z.array(z.lazy(() => CategorySchema)).optional(),
  ancestors: z.array(z.lazy(() => CategorySchema)).optional(),
  custom_fields: z.array(CustomFieldSchema).optional()
});
var ChannelSchema = z.object({
  id: z.string(),
  name: z.string(),
  code: z.string(),
  active: z.boolean(),
  default: z.boolean()
});
var CreditCardSchema = z.object({
  id: z.string(),
  brand: z.string(),
  last4: z.string(),
  month: z.number(),
  year: z.number(),
  name: z.string().nullable(),
  default: z.boolean(),
  gateway_payment_profile_id: z.string().nullable()
});
var CurrencySchema = z.object({
  iso_code: z.string(),
  name: z.string(),
  symbol: z.string()
});
var NewsletterSubscriberSchema = z.object({
  id: z.string(),
  email: z.string(),
  created_at: z.string(),
  updated_at: z.string(),
  verified: z.boolean(),
  verified_at: z.string().nullable(),
  customer_id: z.string().nullable()
});

// src/zod/generated/Customer.ts
var CustomerSchema = z.object({
  id: z.string(),
  email: z.string(),
  first_name: z.string().nullable(),
  last_name: z.string().nullable(),
  phone: z.string().nullable(),
  accepts_email_marketing: z.boolean(),
  full_name: z.string(),
  available_store_credit_total: z.string(),
  display_available_store_credit_total: z.string(),
  addresses: z.array(AddressSchema),
  default_billing_address: AddressSchema.nullable(),
  default_shipping_address: AddressSchema.nullable(),
  newsletter_subscriber: NewsletterSubscriberSchema.nullable()
});
var DigitalSchema = z.object({
  id: z.string(),
  created_at: z.string(),
  updated_at: z.string(),
  variant_id: z.string().nullable()
});
var GiftCardBatchSchema = z.object({
  id: z.string(),
  codes_count: z.number(),
  currency: z.string().nullable(),
  prefix: z.string().nullable(),
  created_at: z.string(),
  updated_at: z.string(),
  amount: z.string().nullable(),
  expires_at: z.string().nullable(),
  created_by_id: z.string().nullable()
});
var InvitationSchema = z.object({
  id: z.string(),
  email: z.string(),
  resource_type: z.string().nullable(),
  inviter_type: z.string().nullable(),
  invitee_type: z.string().nullable(),
  created_at: z.string(),
  updated_at: z.string(),
  status: z.string(),
  resource_id: z.string().nullable(),
  inviter_id: z.string().nullable(),
  invitee_id: z.string().nullable(),
  role_id: z.string().nullable(),
  expires_at: z.string().nullable(),
  accepted_at: z.string().nullable()
});
var LocaleSchema = z.object({
  code: z.string(),
  name: z.string(),
  default: z.boolean(),
  rtl: z.boolean()
});
var MediaSchema = z.object({
  id: z.string(),
  product_id: z.string().nullable(),
  variant_ids: z.array(z.string()),
  position: z.number(),
  alt: z.string().nullable(),
  media_type: z.string(),
  focal_point_x: z.number().nullable(),
  focal_point_y: z.number().nullable(),
  external_video_url: z.string().nullable(),
  original_url: z.string().nullable(),
  mini_url: z.string().nullable(),
  small_url: z.string().nullable(),
  medium_url: z.string().nullable(),
  large_url: z.string().nullable(),
  xlarge_url: z.string().nullable(),
  og_image_url: z.string().nullable()
});
var OptionTypeSchema = z.object({
  id: z.string(),
  name: z.string(),
  label: z.string(),
  position: z.number(),
  kind: z.string()
});
var OrderSchema = z.object({
  id: z.string(),
  market_id: z.string().nullable(),
  channel_id: z.string().nullable(),
  number: z.string(),
  email: z.string(),
  customer_note: z.string().nullable(),
  currency: z.string(),
  locale: z.string().nullable(),
  total_quantity: z.number(),
  fulfillment_status: z.string().nullable(),
  payment_status: z.string().nullable(),
  completed_at: z.string().nullable(),
  item_total: z.string().nullable(),
  display_item_total: z.string().nullable(),
  adjustment_total: z.string().nullable(),
  display_adjustment_total: z.string().nullable(),
  discount_total: z.string().nullable(),
  display_discount_total: z.string().nullable(),
  tax_total: z.string().nullable(),
  display_tax_total: z.string().nullable(),
  included_tax_total: z.string().nullable(),
  display_included_tax_total: z.string().nullable(),
  additional_tax_total: z.string().nullable(),
  display_additional_tax_total: z.string().nullable(),
  total: z.string().nullable(),
  display_total: z.string().nullable(),
  gift_card_total: z.string().nullable(),
  display_gift_card_total: z.string().nullable(),
  amount_due: z.string().nullable(),
  display_amount_due: z.string().nullable(),
  delivery_total: z.string().nullable(),
  display_delivery_total: z.string().nullable(),
  store_credit_total: z.string().nullable(),
  display_store_credit_total: z.string().nullable(),
  covered_by_store_credit: z.boolean(),
  discounts: z.array(DiscountSchema),
  items: z.array(LineItemSchema),
  fulfillments: z.array(FulfillmentSchema),
  payments: z.array(PaymentSchema),
  billing_address: AddressSchema.nullable(),
  shipping_address: AddressSchema.nullable(),
  gift_card: GiftCardSchema.nullable(),
  market: z.lazy(() => MarketSchema).nullable()
});
var PaymentSessionSchema = z.object({
  id: z.string(),
  status: z.string(),
  currency: z.string(),
  external_id: z.string(),
  external_data: z.record(z.string(), z.unknown()),
  customer_external_id: z.string().nullable(),
  expires_at: z.string().nullable(),
  amount: z.string(),
  payment_method_id: z.string(),
  order_id: z.string(),
  payment_method: PaymentMethodSchema,
  payment: PaymentSchema.optional()
});

// src/zod/generated/PaymentGroup.ts
var PaymentGroupSchema = z.object({
  id: z.string(),
  status: z.string(),
  currency: z.string(),
  amount: z.string(),
  completed_at: z.string().nullable(),
  orders: z.array(OrderSchema).optional(),
  payment_sessions: z.array(PaymentSessionSchema).optional()
});
var PaymentSetupSessionSchema = z.object({
  id: z.string(),
  status: z.string(),
  external_id: z.string().nullable(),
  external_client_secret: z.string().nullable(),
  external_data: z.record(z.string(), z.unknown()),
  payment_method_id: z.string().nullable(),
  payment_source_id: z.string().nullable(),
  payment_source_type: z.string().nullable(),
  customer_id: z.string().nullable(),
  payment_method: PaymentMethodSchema
});
var PaymentSourceSchema = z.object({
  id: z.string(),
  gateway_payment_profile_id: z.string().nullable()
});
var PolicySchema = z.object({
  id: z.string(),
  name: z.string(),
  slug: z.string(),
  body: z.string().nullable(),
  body_html: z.string().nullable()
});
var PostSchema = z.object({
  id: z.string(),
  title: z.string(),
  slug: z.string(),
  excerpt: z.string().nullable(),
  author: z.string().nullable(),
  published_at: z.string().nullable(),
  cover_image_url: z.string().nullable(),
  body: z.string().nullable(),
  body_html: z.string().nullable(),
  seo_title: z.string().nullable(),
  seo_description: z.string().nullable()
});
var PriceSchema = z.object({
  id: z.string(),
  amount: z.string().nullable(),
  amount_in_cents: z.number().nullable(),
  compare_at_amount: z.string().nullable(),
  compare_at_amount_in_cents: z.number().nullable(),
  currency: z.string().nullable(),
  display_amount: z.string().nullable(),
  display_compare_at_amount: z.string().nullable(),
  price_list_id: z.string().nullable()
});
var PriceHistorySchema = z.object({
  id: z.string(),
  amount: z.string(),
  amount_in_cents: z.number(),
  currency: z.string(),
  display_amount: z.string(),
  recorded_at: z.string()
});
var VariantSchema = z.object({
  id: z.string(),
  product_id: z.string(),
  sku: z.string().nullable(),
  options_text: z.string(),
  track_inventory: z.boolean(),
  media_count: z.number(),
  preorder_ships_at: z.string().nullable(),
  thumbnail_url: z.string().nullable(),
  purchasable: z.boolean(),
  in_stock: z.boolean(),
  backorderable: z.boolean(),
  preorder: z.boolean(),
  weight: z.number().nullable(),
  height: z.number().nullable(),
  width: z.number().nullable(),
  depth: z.number().nullable(),
  price: PriceSchema,
  original_price: PriceSchema.nullable(),
  primary_media: MediaSchema.optional(),
  media: z.array(MediaSchema).optional(),
  option_values: z.array(OptionValueSchema),
  custom_fields: z.array(CustomFieldSchema).optional(),
  prior_price: PriceHistorySchema.nullable().optional()
});

// src/zod/generated/Product.ts
var ProductSchema = z.object({
  id: z.string(),
  name: z.string(),
  slug: z.string(),
  meta_title: z.string().nullable(),
  meta_description: z.string().nullable(),
  meta_keywords: z.string().nullable(),
  variant_count: z.number(),
  available_on: z.string().nullable(),
  preorder_ships_at: z.string().nullable(),
  purchasable: z.boolean(),
  preorder: z.boolean(),
  in_stock: z.boolean(),
  backorderable: z.boolean(),
  available: z.boolean(),
  description: z.string().nullable(),
  description_html: z.string().nullable(),
  default_variant_id: z.string(),
  thumbnail_url: z.string().nullable(),
  tags: z.array(z.string()),
  price: PriceSchema,
  original_price: PriceSchema.nullable(),
  primary_media: MediaSchema.optional(),
  media: z.array(MediaSchema).optional(),
  variants: z.array(VariantSchema).optional(),
  default_variant: VariantSchema.optional(),
  option_types: z.array(OptionTypeSchema).optional(),
  option_values: z.array(OptionValueSchema).optional(),
  categories: z.array(z.lazy(() => CategorySchema)).optional(),
  custom_fields: z.array(CustomFieldSchema).optional(),
  prior_price: PriceHistorySchema.nullable().optional()
});
var ProductFilterAvailabilityOptionSchema = z.object({
  id: z.string(),
  count: z.number()
});

// src/zod/generated/ProductFilterAvailability.ts
var ProductFilterAvailabilitySchema = z.object({
  id: z.string(),
  type: z.any(),
  options: z.array(ProductFilterAvailabilityOptionSchema)
});
var ProductFilterCategoryOptionSchema = z.object({
  id: z.string(),
  name: z.string(),
  permalink: z.string(),
  count: z.number()
});

// src/zod/generated/ProductFilterCategory.ts
var ProductFilterCategorySchema = z.object({
  id: z.string(),
  type: z.any(),
  options: z.array(ProductFilterCategoryOptionSchema)
});
var ProductFilterOptionValueSchema = z.object({
  id: z.string(),
  name: z.string(),
  label: z.string(),
  position: z.number(),
  color_code: z.string().nullable(),
  image_url: z.string().nullable(),
  count: z.number()
});

// src/zod/generated/ProductFilterOption.ts
var ProductFilterOptionSchema = z.object({
  id: z.string(),
  type: z.any(),
  name: z.string(),
  label: z.string(),
  kind: z.string(),
  options: z.array(ProductFilterOptionValueSchema)
});
var ProductFilterPriceRangeSchema = z.object({
  id: z.string(),
  type: z.any(),
  min: z.number(),
  max: z.number(),
  currency: z.string()
});
var ProductFilterSortOptionSchema = z.object({
  id: z.string()
});
var ProductFiltersSchema = z.object({
  id: z.string(),
  default_sort: z.string(),
  total_count: z.number(),
  filters: z.array(z.any()),
  sort_options: z.array(ProductFilterSortOptionSchema)
});
var ProductPublicationSchema = z.object({
  id: z.string(),
  published_at: z.string().nullable(),
  unpublished_at: z.string().nullable(),
  product_id: z.string(),
  channel_id: z.string()
});
var PromotionSchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  code: z.string().nullable()
});
var RefundSchema = z.object({
  id: z.string(),
  transaction_id: z.string().nullable(),
  amount: z.string().nullable(),
  payment_id: z.string().nullable(),
  refund_reason_id: z.string().nullable(),
  reimbursement_id: z.string().nullable()
});
var ReturnAuthorizationSchema = z.object({
  id: z.string(),
  number: z.string(),
  status: z.string(),
  order_id: z.string().nullable(),
  stock_location_id: z.string().nullable(),
  return_authorization_reason_id: z.string().nullable()
});
var ReturnItemSchema = z.object({
  id: z.string(),
  reception_status: z.string().nullable(),
  acceptance_status: z.string().nullable(),
  created_at: z.string(),
  updated_at: z.string(),
  pre_tax_amount: z.string().nullable(),
  included_tax_total: z.string().nullable(),
  additional_tax_total: z.string().nullable(),
  inventory_unit_id: z.string().nullable(),
  return_authorization_id: z.string().nullable(),
  customer_return_id: z.string().nullable(),
  reimbursement_id: z.string().nullable(),
  exchange_variant_id: z.string().nullable()
});
var StockReservationSchema = z.object({
  id: z.string()
});
var StoreCreditSchema = z.object({
  id: z.string(),
  amount: z.string(),
  amount_used: z.string(),
  amount_remaining: z.string(),
  display_amount: z.string(),
  display_amount_used: z.string(),
  display_amount_remaining: z.string(),
  currency: z.string()
});
var WishlistItemSchema = z.object({
  id: z.string(),
  variant_id: z.string(),
  wishlist_id: z.string(),
  quantity: z.number(),
  variant: VariantSchema
});

// src/zod/generated/Wishlist.ts
var WishlistSchema = z.object({
  id: z.string(),
  name: z.string(),
  token: z.string(),
  is_default: z.boolean(),
  is_private: z.boolean(),
  items: z.array(WishlistItemSchema).optional()
});

export { AddressSchema, BaseSchema, CartSchema, CategorySchema, ChannelSchema, CountrySchema, CreditCardSchema, CurrencySchema, CustomFieldSchema, CustomerSchema, DeliveryMethodSchema, DeliveryRateSchema, DigitalLinkSchema, DigitalSchema, DiscountSchema, FulfillmentSchema, GiftCardBatchSchema, GiftCardSchema, InvitationSchema, LineItemSchema, LocaleSchema, MarketSchema, MediaSchema, NewsletterSubscriberSchema, OptionTypeSchema, OptionValueSchema, OrderSchema, PaymentGroupSchema, PaymentMethodSchema, PaymentSchema, PaymentSessionSchema, PaymentSetupSessionSchema, PaymentSourceSchema, PolicySchema, PostSchema, PriceHistorySchema, PriceSchema, ProductFilterAvailabilityOptionSchema, ProductFilterAvailabilitySchema, ProductFilterCategoryOptionSchema, ProductFilterCategorySchema, ProductFilterOptionSchema, ProductFilterOptionValueSchema, ProductFilterPriceRangeSchema, ProductFilterSortOptionSchema, ProductFiltersSchema, ProductPublicationSchema, ProductSchema, PromotionSchema, RefundSchema, ReturnAuthorizationSchema, ReturnItemSchema, StateSchema, StockLocationSchema, StockReservationSchema, StoreCreditSchema, VariantSchema, WishlistItemSchema, WishlistSchema };
//# sourceMappingURL=index.js.map
//# sourceMappingURL=index.js.map