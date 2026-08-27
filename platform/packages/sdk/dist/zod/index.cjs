'use strict';

var zod = require('zod');

// src/zod/generated/Address.ts
var AddressSchema = zod.z.object({
  id: zod.z.string(),
  first_name: zod.z.string().nullable(),
  last_name: zod.z.string().nullable(),
  full_name: zod.z.string(),
  address1: zod.z.string().nullable(),
  address2: zod.z.string().nullable(),
  postal_code: zod.z.string().nullable(),
  city: zod.z.string().nullable(),
  phone: zod.z.string().nullable(),
  company: zod.z.string().nullable(),
  country_name: zod.z.string(),
  country_iso: zod.z.string(),
  state_text: zod.z.string().nullable(),
  state_abbr: zod.z.string().nullable(),
  quick_checkout: zod.z.boolean(),
  is_default_billing: zod.z.boolean(),
  is_default_shipping: zod.z.boolean(),
  state_name: zod.z.string().nullable()
});
var BackInStockSubscriptionSchema = zod.z.object({
  id: zod.z.string(),
  product_id: zod.z.string().nullable(),
  email: zod.z.string(),
  status: zod.z.string(),
  created_at: zod.z.string()
});
var BaseSchema = zod.z.object({
  id: zod.z.string()
});
var DiscountSchema = zod.z.object({
  id: zod.z.string(),
  promotion_id: zod.z.string(),
  name: zod.z.string(),
  description: zod.z.string().nullable(),
  code: zod.z.string().nullable(),
  amount: zod.z.string().nullable(),
  display_amount: zod.z.string().nullable()
});
var DeliveryMethodSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  code: zod.z.string().nullable()
});
var DeliveryRateSchema = zod.z.object({
  id: zod.z.string(),
  delivery_method_id: zod.z.string(),
  name: zod.z.string(),
  selected: zod.z.boolean(),
  cost: zod.z.string(),
  total: zod.z.string(),
  additional_tax_total: zod.z.string(),
  included_tax_total: zod.z.string(),
  tax_total: zod.z.string(),
  display_cost: zod.z.string(),
  display_total: zod.z.string(),
  display_additional_tax_total: zod.z.string(),
  display_included_tax_total: zod.z.string(),
  display_tax_total: zod.z.string(),
  delivery_method: DeliveryMethodSchema
});
var StockLocationSchema = zod.z.object({
  id: zod.z.string(),
  state_abbr: zod.z.string().nullable(),
  name: zod.z.string(),
  address1: zod.z.string().nullable(),
  city: zod.z.string().nullable(),
  zipcode: zod.z.string().nullable(),
  country_iso: zod.z.string().nullable(),
  country_name: zod.z.string().nullable(),
  state_text: zod.z.string().nullable()
});

// src/zod/generated/Fulfillment.ts
var FulfillmentSchema = zod.z.object({
  id: zod.z.string(),
  number: zod.z.string(),
  tracking: zod.z.string().nullable(),
  tracking_url: zod.z.string().nullable(),
  cost: zod.z.string().nullable(),
  display_cost: zod.z.string().nullable(),
  total: zod.z.string().nullable(),
  display_total: zod.z.string().nullable(),
  discount_total: zod.z.string().nullable(),
  display_discount_total: zod.z.string().nullable(),
  additional_tax_total: zod.z.string().nullable(),
  display_additional_tax_total: zod.z.string().nullable(),
  included_tax_total: zod.z.string().nullable(),
  display_included_tax_total: zod.z.string().nullable(),
  tax_total: zod.z.string().nullable(),
  display_tax_total: zod.z.string().nullable(),
  status: zod.z.string(),
  fulfillment_type: zod.z.string(),
  fulfilled_at: zod.z.string().nullable(),
  items: zod.z.array(zod.z.object({ item_id: zod.z.any() })),
  delivery_method: DeliveryMethodSchema,
  stock_location: StockLocationSchema,
  delivery_rates: zod.z.array(DeliveryRateSchema)
});
var GiftCardSchema = zod.z.object({
  id: zod.z.string(),
  code: zod.z.string(),
  status: zod.z.string(),
  currency: zod.z.string(),
  amount: zod.z.string().nullable(),
  amount_used: zod.z.string().nullable(),
  amount_authorized: zod.z.string().nullable(),
  amount_remaining: zod.z.string().nullable(),
  display_amount: zod.z.string().nullable(),
  display_amount_used: zod.z.string().nullable(),
  display_amount_remaining: zod.z.string().nullable(),
  expires_at: zod.z.string().nullable(),
  redeemed_at: zod.z.string().nullable(),
  expired: zod.z.boolean(),
  active: zod.z.boolean()
});
var DigitalLinkSchema = zod.z.object({
  id: zod.z.string(),
  access_counter: zod.z.number(),
  filename: zod.z.string(),
  content_type: zod.z.string(),
  download_url: zod.z.string(),
  authorizable: zod.z.boolean(),
  expired: zod.z.boolean(),
  access_limit_exceeded: zod.z.boolean()
});
var OptionValueSchema = zod.z.object({
  id: zod.z.string(),
  option_type_id: zod.z.string(),
  name: zod.z.string(),
  label: zod.z.string(),
  position: zod.z.number(),
  color_code: zod.z.string().nullable(),
  option_type_name: zod.z.string(),
  option_type_label: zod.z.string(),
  image_url: zod.z.string().nullable()
});

// src/zod/generated/LineItem.ts
var LineItemSchema = zod.z.object({
  id: zod.z.string(),
  variant_id: zod.z.string(),
  preorder: zod.z.boolean(),
  preorder_ships_at: zod.z.string().nullable(),
  quantity: zod.z.number(),
  currency: zod.z.string(),
  name: zod.z.string(),
  slug: zod.z.string(),
  options_text: zod.z.string(),
  price: zod.z.string().nullable(),
  display_price: zod.z.string().nullable(),
  total: zod.z.string().nullable(),
  display_total: zod.z.string().nullable(),
  adjustment_total: zod.z.string().nullable(),
  display_adjustment_total: zod.z.string().nullable(),
  additional_tax_total: zod.z.string().nullable(),
  display_additional_tax_total: zod.z.string().nullable(),
  included_tax_total: zod.z.string().nullable(),
  display_included_tax_total: zod.z.string().nullable(),
  discount_total: zod.z.string().nullable(),
  display_discount_total: zod.z.string().nullable(),
  pre_tax_amount: zod.z.string().nullable(),
  display_pre_tax_amount: zod.z.string().nullable(),
  discounted_amount: zod.z.string().nullable(),
  display_discounted_amount: zod.z.string().nullable(),
  display_compare_at_amount: zod.z.string().nullable(),
  compare_at_amount: zod.z.string().nullable(),
  thumbnail_url: zod.z.string().nullable(),
  option_values: zod.z.array(OptionValueSchema),
  digital_links: zod.z.array(DigitalLinkSchema)
});
var StateSchema = zod.z.object({
  abbr: zod.z.string(),
  name: zod.z.string()
});

// src/zod/generated/Country.ts
var CountrySchema = zod.z.object({
  iso: zod.z.string(),
  iso3: zod.z.string(),
  name: zod.z.string(),
  states_required: zod.z.boolean(),
  zipcode_required: zod.z.boolean(),
  states: zod.z.array(StateSchema).optional(),
  market: zod.z.lazy(() => MarketSchema).nullable().optional()
});

// src/zod/generated/Market.ts
var MarketSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  currency: zod.z.string(),
  default_locale: zod.z.string(),
  tax_inclusive: zod.z.boolean(),
  default: zod.z.boolean(),
  country_isos: zod.z.array(zod.z.string()),
  supported_locales: zod.z.array(zod.z.string()),
  countries: zod.z.array(zod.z.lazy(() => CountrySchema)).optional()
});
var PaymentMethodSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  description: zod.z.string().nullable(),
  type: zod.z.string(),
  session_required: zod.z.boolean(),
  source_required: zod.z.boolean()
});

// src/zod/generated/Payment.ts
var PaymentSchema = zod.z.object({
  id: zod.z.string(),
  payment_method_id: zod.z.string(),
  response_code: zod.z.string().nullable(),
  number: zod.z.string(),
  amount: zod.z.string().nullable(),
  display_amount: zod.z.string().nullable(),
  status: zod.z.string(),
  source_type: zod.z.string().nullable(),
  source_id: zod.z.string().nullable(),
  source: zod.z.any(),
  payment_method: PaymentMethodSchema
});

// src/zod/generated/Cart.ts
var CartSchema = zod.z.object({
  id: zod.z.string(),
  market_id: zod.z.string().nullable(),
  number: zod.z.string(),
  token: zod.z.string(),
  email: zod.z.string().nullable(),
  customer_note: zod.z.string().nullable(),
  currency: zod.z.string(),
  locale: zod.z.string().nullable(),
  total_quantity: zod.z.number(),
  warnings: zod.z.array(zod.z.any()),
  item_total: zod.z.string().nullable(),
  display_item_total: zod.z.string().nullable(),
  adjustment_total: zod.z.string().nullable(),
  display_adjustment_total: zod.z.string().nullable(),
  discount_total: zod.z.string().nullable(),
  display_discount_total: zod.z.string().nullable(),
  tax_total: zod.z.string().nullable(),
  display_tax_total: zod.z.string().nullable(),
  included_tax_total: zod.z.string().nullable(),
  display_included_tax_total: zod.z.string().nullable(),
  additional_tax_total: zod.z.string().nullable(),
  display_additional_tax_total: zod.z.string().nullable(),
  total: zod.z.string().nullable(),
  display_total: zod.z.string().nullable(),
  gift_card_total: zod.z.string().nullable(),
  display_gift_card_total: zod.z.string().nullable(),
  amount_due: zod.z.string().nullable(),
  display_amount_due: zod.z.string().nullable(),
  delivery_total: zod.z.string().nullable(),
  display_delivery_total: zod.z.string().nullable(),
  store_credit_total: zod.z.string().nullable(),
  display_store_credit_total: zod.z.string().nullable(),
  covered_by_store_credit: zod.z.boolean(),
  current_step: zod.z.string(),
  completed_steps: zod.z.array(zod.z.string()),
  requirements: zod.z.array(zod.z.object({ step: zod.z.string(), field: zod.z.string(), message: zod.z.string() })),
  shipping_eq_billing_address: zod.z.boolean(),
  discounts: zod.z.array(DiscountSchema),
  items: zod.z.array(LineItemSchema),
  fulfillments: zod.z.array(FulfillmentSchema),
  payments: zod.z.array(PaymentSchema),
  billing_address: AddressSchema.nullable(),
  shipping_address: AddressSchema.nullable(),
  payment_methods: zod.z.array(PaymentMethodSchema),
  gift_card: GiftCardSchema.nullable(),
  market: zod.z.lazy(() => MarketSchema).nullable()
});
var CustomFieldSchema = zod.z.object({
  id: zod.z.string(),
  label: zod.z.string(),
  type: zod.z.string(),
  field_type: zod.z.string(),
  key: zod.z.string(),
  value: zod.z.any()
});

// src/zod/generated/Category.ts
var CategorySchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  permalink: zod.z.string(),
  position: zod.z.number(),
  depth: zod.z.number(),
  meta_title: zod.z.string().nullable(),
  meta_description: zod.z.string().nullable(),
  meta_keywords: zod.z.string().nullable(),
  children_count: zod.z.number(),
  parent_id: zod.z.string().nullable(),
  description: zod.z.string(),
  description_html: zod.z.string(),
  image_url: zod.z.string().nullable(),
  square_image_url: zod.z.string().nullable(),
  is_root: zod.z.boolean(),
  is_child: zod.z.boolean(),
  is_leaf: zod.z.boolean(),
  parent: zod.z.lazy(() => CategorySchema).optional(),
  children: zod.z.array(zod.z.lazy(() => CategorySchema)).optional(),
  ancestors: zod.z.array(zod.z.lazy(() => CategorySchema)).optional(),
  custom_fields: zod.z.array(CustomFieldSchema).optional()
});
var ChannelSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  code: zod.z.string(),
  active: zod.z.boolean(),
  default: zod.z.boolean()
});
var ContactMessageSchema = zod.z.object({
  id: zod.z.string(),
  kind: zod.z.string(),
  name: zod.z.string().nullable(),
  email: zod.z.string(),
  subject: zod.z.string().nullable(),
  body: zod.z.string(),
  status: zod.z.string(),
  created_at: zod.z.string()
});
var CreditCardSchema = zod.z.object({
  id: zod.z.string(),
  brand: zod.z.string(),
  last4: zod.z.string(),
  month: zod.z.number(),
  year: zod.z.number(),
  name: zod.z.string().nullable(),
  default: zod.z.boolean(),
  gateway_payment_profile_id: zod.z.string().nullable()
});
var CurrencySchema = zod.z.object({
  iso_code: zod.z.string(),
  name: zod.z.string(),
  symbol: zod.z.string()
});
var NewsletterSubscriberSchema = zod.z.object({
  id: zod.z.string(),
  email: zod.z.string(),
  created_at: zod.z.string(),
  updated_at: zod.z.string(),
  verified: zod.z.boolean(),
  verified_at: zod.z.string().nullable(),
  customer_id: zod.z.string().nullable()
});

// src/zod/generated/Customer.ts
var CustomerSchema = zod.z.object({
  id: zod.z.string(),
  email: zod.z.string(),
  first_name: zod.z.string().nullable(),
  last_name: zod.z.string().nullable(),
  phone: zod.z.string().nullable(),
  accepts_email_marketing: zod.z.boolean(),
  full_name: zod.z.string(),
  available_store_credit_total: zod.z.string(),
  display_available_store_credit_total: zod.z.string(),
  addresses: zod.z.array(AddressSchema),
  default_billing_address: AddressSchema.nullable(),
  default_shipping_address: AddressSchema.nullable(),
  newsletter_subscriber: NewsletterSubscriberSchema.nullable()
});
var DigitalSchema = zod.z.object({
  id: zod.z.string(),
  created_at: zod.z.string(),
  updated_at: zod.z.string(),
  variant_id: zod.z.string().nullable()
});
var GiftCardBatchSchema = zod.z.object({
  id: zod.z.string(),
  codes_count: zod.z.number(),
  currency: zod.z.string().nullable(),
  prefix: zod.z.string().nullable(),
  created_at: zod.z.string(),
  updated_at: zod.z.string(),
  amount: zod.z.string().nullable(),
  expires_at: zod.z.string().nullable(),
  created_by_id: zod.z.string().nullable()
});
var InvitationSchema = zod.z.object({
  id: zod.z.string(),
  email: zod.z.string(),
  resource_type: zod.z.string().nullable(),
  inviter_type: zod.z.string().nullable(),
  invitee_type: zod.z.string().nullable(),
  created_at: zod.z.string(),
  updated_at: zod.z.string(),
  status: zod.z.string(),
  resource_id: zod.z.string().nullable(),
  inviter_id: zod.z.string().nullable(),
  invitee_id: zod.z.string().nullable(),
  role_id: zod.z.string().nullable(),
  expires_at: zod.z.string().nullable(),
  accepted_at: zod.z.string().nullable()
});
var LocaleSchema = zod.z.object({
  code: zod.z.string(),
  name: zod.z.string(),
  default: zod.z.boolean(),
  rtl: zod.z.boolean()
});
var MediaSchema = zod.z.object({
  id: zod.z.string(),
  product_id: zod.z.string().nullable(),
  variant_ids: zod.z.array(zod.z.string()),
  position: zod.z.number(),
  alt: zod.z.string().nullable(),
  media_type: zod.z.string(),
  focal_point_x: zod.z.number().nullable(),
  focal_point_y: zod.z.number().nullable(),
  external_video_url: zod.z.string().nullable(),
  original_url: zod.z.string().nullable(),
  mini_url: zod.z.string().nullable(),
  small_url: zod.z.string().nullable(),
  medium_url: zod.z.string().nullable(),
  large_url: zod.z.string().nullable(),
  xlarge_url: zod.z.string().nullable(),
  og_image_url: zod.z.string().nullable()
});
var OptionTypeSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  label: zod.z.string(),
  position: zod.z.number(),
  kind: zod.z.string()
});
var OrderSchema = zod.z.object({
  id: zod.z.string(),
  parent_id: zod.z.string().nullable(),
  children_ids: zod.z.any(),
  is_parent: zod.z.boolean(),
  is_child: zod.z.boolean(),
  is_single: zod.z.boolean(),
  market_id: zod.z.string().nullable(),
  channel_id: zod.z.string().nullable(),
  number: zod.z.string(),
  email: zod.z.string(),
  customer_note: zod.z.string().nullable(),
  currency: zod.z.string(),
  locale: zod.z.string().nullable(),
  total_quantity: zod.z.number(),
  fulfillment_status: zod.z.string().nullable(),
  payment_status: zod.z.string().nullable(),
  completed_at: zod.z.string().nullable(),
  item_total: zod.z.string().nullable(),
  display_item_total: zod.z.string().nullable(),
  adjustment_total: zod.z.string().nullable(),
  display_adjustment_total: zod.z.string().nullable(),
  discount_total: zod.z.string().nullable(),
  display_discount_total: zod.z.string().nullable(),
  tax_total: zod.z.string().nullable(),
  display_tax_total: zod.z.string().nullable(),
  included_tax_total: zod.z.string().nullable(),
  display_included_tax_total: zod.z.string().nullable(),
  additional_tax_total: zod.z.string().nullable(),
  display_additional_tax_total: zod.z.string().nullable(),
  total: zod.z.string().nullable(),
  display_total: zod.z.string().nullable(),
  gift_card_total: zod.z.string().nullable(),
  display_gift_card_total: zod.z.string().nullable(),
  amount_due: zod.z.string().nullable(),
  display_amount_due: zod.z.string().nullable(),
  delivery_total: zod.z.string().nullable(),
  display_delivery_total: zod.z.string().nullable(),
  store_credit_total: zod.z.string().nullable(),
  display_store_credit_total: zod.z.string().nullable(),
  covered_by_store_credit: zod.z.boolean(),
  discounts: zod.z.array(DiscountSchema),
  items: zod.z.array(LineItemSchema),
  fulfillments: zod.z.array(FulfillmentSchema),
  payments: zod.z.array(PaymentSchema),
  billing_address: AddressSchema.nullable(),
  shipping_address: AddressSchema.nullable(),
  gift_card: GiftCardSchema.nullable(),
  market: zod.z.lazy(() => MarketSchema).nullable()
});
var PaymentSessionSchema = zod.z.object({
  id: zod.z.string(),
  status: zod.z.string(),
  currency: zod.z.string(),
  external_id: zod.z.string(),
  external_data: zod.z.record(zod.z.string(), zod.z.unknown()),
  customer_external_id: zod.z.string().nullable(),
  expires_at: zod.z.string().nullable(),
  amount: zod.z.string(),
  payment_method_id: zod.z.string(),
  order_id: zod.z.string(),
  payment_method: PaymentMethodSchema,
  payment: PaymentSchema.optional()
});

// src/zod/generated/PaymentCombination.ts
var PaymentCombinationSchema = zod.z.object({
  id: zod.z.string(),
  status: zod.z.string(),
  currency: zod.z.string(),
  expires_at: zod.z.string().nullable(),
  completed_at: zod.z.string().nullable(),
  amount: zod.z.string(),
  orders: zod.z.array(OrderSchema).optional(),
  payment_session: PaymentSessionSchema.optional()
});
var PaymentSetupSessionSchema = zod.z.object({
  id: zod.z.string(),
  status: zod.z.string(),
  external_id: zod.z.string().nullable(),
  external_client_secret: zod.z.string().nullable(),
  external_data: zod.z.record(zod.z.string(), zod.z.unknown()),
  payment_method_id: zod.z.string().nullable(),
  payment_source_id: zod.z.string().nullable(),
  payment_source_type: zod.z.string().nullable(),
  customer_id: zod.z.string().nullable(),
  payment_method: PaymentMethodSchema
});
var PaymentSourceSchema = zod.z.object({
  id: zod.z.string(),
  gateway_payment_profile_id: zod.z.string().nullable()
});
var PolicySchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  slug: zod.z.string(),
  body: zod.z.string().nullable(),
  body_html: zod.z.string().nullable()
});
var PostSchema = zod.z.object({
  id: zod.z.string(),
  title: zod.z.string(),
  slug: zod.z.string(),
  excerpt: zod.z.string().nullable(),
  author: zod.z.string().nullable(),
  published_at: zod.z.string().nullable(),
  cover_image_url: zod.z.string().nullable(),
  body: zod.z.string().nullable(),
  body_html: zod.z.string().nullable(),
  seo_title: zod.z.string().nullable(),
  seo_description: zod.z.string().nullable()
});
var PriceSchema = zod.z.object({
  id: zod.z.string(),
  amount: zod.z.string().nullable(),
  amount_in_cents: zod.z.number().nullable(),
  compare_at_amount: zod.z.string().nullable(),
  compare_at_amount_in_cents: zod.z.number().nullable(),
  currency: zod.z.string().nullable(),
  display_amount: zod.z.string().nullable(),
  display_compare_at_amount: zod.z.string().nullable(),
  price_list_id: zod.z.string().nullable()
});
var PriceHistorySchema = zod.z.object({
  id: zod.z.string(),
  amount: zod.z.string(),
  amount_in_cents: zod.z.number(),
  currency: zod.z.string(),
  display_amount: zod.z.string(),
  recorded_at: zod.z.string()
});
var VariantSchema = zod.z.object({
  id: zod.z.string(),
  product_id: zod.z.string(),
  sku: zod.z.string().nullable(),
  options_text: zod.z.string(),
  track_inventory: zod.z.boolean(),
  media_count: zod.z.number(),
  preorder_ships_at: zod.z.string().nullable(),
  thumbnail_url: zod.z.string().nullable(),
  purchasable: zod.z.boolean(),
  in_stock: zod.z.boolean(),
  backorderable: zod.z.boolean(),
  preorder: zod.z.boolean(),
  weight: zod.z.number().nullable(),
  height: zod.z.number().nullable(),
  width: zod.z.number().nullable(),
  depth: zod.z.number().nullable(),
  price: PriceSchema,
  original_price: PriceSchema.nullable(),
  primary_media: MediaSchema.optional(),
  media: zod.z.array(MediaSchema).optional(),
  option_values: zod.z.array(OptionValueSchema),
  custom_fields: zod.z.array(CustomFieldSchema).optional(),
  prior_price: PriceHistorySchema.nullable().optional()
});

// src/zod/generated/Product.ts
var ProductSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  slug: zod.z.string(),
  meta_title: zod.z.string().nullable(),
  meta_description: zod.z.string().nullable(),
  meta_keywords: zod.z.string().nullable(),
  variant_count: zod.z.number(),
  available_on: zod.z.string().nullable(),
  preorder_ships_at: zod.z.string().nullable(),
  purchasable: zod.z.boolean(),
  preorder: zod.z.boolean(),
  in_stock: zod.z.boolean(),
  backorderable: zod.z.boolean(),
  available: zod.z.boolean(),
  description: zod.z.string().nullable(),
  description_html: zod.z.string().nullable(),
  default_variant_id: zod.z.string(),
  thumbnail_url: zod.z.string().nullable(),
  tags: zod.z.array(zod.z.string()),
  average_rating: zod.z.number().nullable(),
  review_count: zod.z.number(),
  price: PriceSchema,
  original_price: PriceSchema.nullable(),
  primary_media: MediaSchema.optional(),
  media: zod.z.array(MediaSchema).optional(),
  variants: zod.z.array(VariantSchema).optional(),
  default_variant: VariantSchema.optional(),
  option_types: zod.z.array(OptionTypeSchema).optional(),
  option_values: zod.z.array(OptionValueSchema).optional(),
  categories: zod.z.array(zod.z.lazy(() => CategorySchema)).optional(),
  custom_fields: zod.z.array(CustomFieldSchema).optional(),
  prior_price: PriceHistorySchema.nullable().optional()
});
var ProductFilterAvailabilityOptionSchema = zod.z.object({
  id: zod.z.string(),
  count: zod.z.number()
});

// src/zod/generated/ProductFilterAvailability.ts
var ProductFilterAvailabilitySchema = zod.z.object({
  id: zod.z.string(),
  type: zod.z.any(),
  options: zod.z.array(ProductFilterAvailabilityOptionSchema)
});
var ProductFilterCategoryOptionSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  permalink: zod.z.string(),
  count: zod.z.number()
});

// src/zod/generated/ProductFilterCategory.ts
var ProductFilterCategorySchema = zod.z.object({
  id: zod.z.string(),
  type: zod.z.any(),
  options: zod.z.array(ProductFilterCategoryOptionSchema)
});
var ProductFilterOptionValueSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  label: zod.z.string(),
  position: zod.z.number(),
  color_code: zod.z.string().nullable(),
  image_url: zod.z.string().nullable(),
  count: zod.z.number()
});

// src/zod/generated/ProductFilterOption.ts
var ProductFilterOptionSchema = zod.z.object({
  id: zod.z.string(),
  type: zod.z.any(),
  name: zod.z.string(),
  label: zod.z.string(),
  kind: zod.z.string(),
  options: zod.z.array(ProductFilterOptionValueSchema)
});
var ProductFilterPriceRangeSchema = zod.z.object({
  id: zod.z.string(),
  type: zod.z.any(),
  min: zod.z.number(),
  max: zod.z.number(),
  currency: zod.z.string()
});
var ProductFilterSortOptionSchema = zod.z.object({
  id: zod.z.string()
});
var ProductFiltersSchema = zod.z.object({
  id: zod.z.string(),
  default_sort: zod.z.string(),
  total_count: zod.z.number(),
  filters: zod.z.array(zod.z.any()),
  sort_options: zod.z.array(ProductFilterSortOptionSchema)
});
var ProductPublicationSchema = zod.z.object({
  id: zod.z.string(),
  published_at: zod.z.string().nullable(),
  unpublished_at: zod.z.string().nullable(),
  product_id: zod.z.string(),
  channel_id: zod.z.string()
});
var PromotionSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  description: zod.z.string().nullable(),
  code: zod.z.string().nullable()
});
var RefundSchema = zod.z.object({
  id: zod.z.string(),
  transaction_id: zod.z.string().nullable(),
  amount: zod.z.string().nullable(),
  payment_id: zod.z.string().nullable(),
  refund_reason_id: zod.z.string().nullable(),
  reimbursement_id: zod.z.string().nullable()
});
var ReturnAuthorizationSchema = zod.z.object({
  id: zod.z.string(),
  number: zod.z.string(),
  status: zod.z.string(),
  order_id: zod.z.string().nullable(),
  stock_location_id: zod.z.string().nullable(),
  return_authorization_reason_id: zod.z.string().nullable()
});
var ReturnItemSchema = zod.z.object({
  id: zod.z.string(),
  reception_status: zod.z.string().nullable(),
  acceptance_status: zod.z.string().nullable(),
  created_at: zod.z.string(),
  updated_at: zod.z.string(),
  pre_tax_amount: zod.z.string().nullable(),
  included_tax_total: zod.z.string().nullable(),
  additional_tax_total: zod.z.string().nullable(),
  inventory_unit_id: zod.z.string().nullable(),
  return_authorization_id: zod.z.string().nullable(),
  customer_return_id: zod.z.string().nullable(),
  reimbursement_id: zod.z.string().nullable(),
  exchange_variant_id: zod.z.string().nullable()
});
var ReviewSchema = zod.z.object({
  id: zod.z.string(),
  product_id: zod.z.string().nullable(),
  user_name: zod.z.string().nullable(),
  rating: zod.z.number(),
  title: zod.z.string().nullable(),
  body: zod.z.string().nullable(),
  verified_purchase: zod.z.boolean(),
  created_at: zod.z.string().nullable()
});
var StockReservationSchema = zod.z.object({
  id: zod.z.string()
});
var StoreCreditSchema = zod.z.object({
  id: zod.z.string(),
  amount: zod.z.string(),
  amount_used: zod.z.string(),
  amount_remaining: zod.z.string(),
  display_amount: zod.z.string(),
  display_amount_used: zod.z.string(),
  display_amount_remaining: zod.z.string(),
  currency: zod.z.string()
});
var WishlistItemSchema = zod.z.object({
  id: zod.z.string(),
  variant_id: zod.z.string(),
  wishlist_id: zod.z.string(),
  quantity: zod.z.number(),
  variant: VariantSchema
});

// src/zod/generated/Wishlist.ts
var WishlistSchema = zod.z.object({
  id: zod.z.string(),
  name: zod.z.string(),
  token: zod.z.string(),
  is_default: zod.z.boolean(),
  is_private: zod.z.boolean(),
  items: zod.z.array(WishlistItemSchema).optional()
});

exports.AddressSchema = AddressSchema;
exports.BackInStockSubscriptionSchema = BackInStockSubscriptionSchema;
exports.BaseSchema = BaseSchema;
exports.CartSchema = CartSchema;
exports.CategorySchema = CategorySchema;
exports.ChannelSchema = ChannelSchema;
exports.ContactMessageSchema = ContactMessageSchema;
exports.CountrySchema = CountrySchema;
exports.CreditCardSchema = CreditCardSchema;
exports.CurrencySchema = CurrencySchema;
exports.CustomFieldSchema = CustomFieldSchema;
exports.CustomerSchema = CustomerSchema;
exports.DeliveryMethodSchema = DeliveryMethodSchema;
exports.DeliveryRateSchema = DeliveryRateSchema;
exports.DigitalLinkSchema = DigitalLinkSchema;
exports.DigitalSchema = DigitalSchema;
exports.DiscountSchema = DiscountSchema;
exports.FulfillmentSchema = FulfillmentSchema;
exports.GiftCardBatchSchema = GiftCardBatchSchema;
exports.GiftCardSchema = GiftCardSchema;
exports.InvitationSchema = InvitationSchema;
exports.LineItemSchema = LineItemSchema;
exports.LocaleSchema = LocaleSchema;
exports.MarketSchema = MarketSchema;
exports.MediaSchema = MediaSchema;
exports.NewsletterSubscriberSchema = NewsletterSubscriberSchema;
exports.OptionTypeSchema = OptionTypeSchema;
exports.OptionValueSchema = OptionValueSchema;
exports.OrderSchema = OrderSchema;
exports.PaymentCombinationSchema = PaymentCombinationSchema;
exports.PaymentMethodSchema = PaymentMethodSchema;
exports.PaymentSchema = PaymentSchema;
exports.PaymentSessionSchema = PaymentSessionSchema;
exports.PaymentSetupSessionSchema = PaymentSetupSessionSchema;
exports.PaymentSourceSchema = PaymentSourceSchema;
exports.PolicySchema = PolicySchema;
exports.PostSchema = PostSchema;
exports.PriceHistorySchema = PriceHistorySchema;
exports.PriceSchema = PriceSchema;
exports.ProductFilterAvailabilityOptionSchema = ProductFilterAvailabilityOptionSchema;
exports.ProductFilterAvailabilitySchema = ProductFilterAvailabilitySchema;
exports.ProductFilterCategoryOptionSchema = ProductFilterCategoryOptionSchema;
exports.ProductFilterCategorySchema = ProductFilterCategorySchema;
exports.ProductFilterOptionSchema = ProductFilterOptionSchema;
exports.ProductFilterOptionValueSchema = ProductFilterOptionValueSchema;
exports.ProductFilterPriceRangeSchema = ProductFilterPriceRangeSchema;
exports.ProductFilterSortOptionSchema = ProductFilterSortOptionSchema;
exports.ProductFiltersSchema = ProductFiltersSchema;
exports.ProductPublicationSchema = ProductPublicationSchema;
exports.ProductSchema = ProductSchema;
exports.PromotionSchema = PromotionSchema;
exports.RefundSchema = RefundSchema;
exports.ReturnAuthorizationSchema = ReturnAuthorizationSchema;
exports.ReturnItemSchema = ReturnItemSchema;
exports.ReviewSchema = ReviewSchema;
exports.StateSchema = StateSchema;
exports.StockLocationSchema = StockLocationSchema;
exports.StockReservationSchema = StockReservationSchema;
exports.StoreCreditSchema = StoreCreditSchema;
exports.VariantSchema = VariantSchema;
exports.WishlistItemSchema = WishlistItemSchema;
exports.WishlistSchema = WishlistSchema;
//# sourceMappingURL=index.cjs.map
//# sourceMappingURL=index.cjs.map