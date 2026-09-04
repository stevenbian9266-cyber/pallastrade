import type { AddressParams, ListParams } from '@pallastrade/sdk-core'
import type {
  Address as AddressType,
  Cart as CartType,
  Fulfillment as FulfillmentType,
  LineItem as LineItemType,
  Order as OrderType,
  PaymentMethod,
} from './generated'

// Re-export all generated types (unprefixed: Product, Order, etc.)
export type {
  Address,
  BackInStockSubscription,
  Base,
  Cart,
  Category,
  ContactMessage,
  Country,
  CreditCard,
  Currency,
  Customer,
  CustomField,
  DeliveryMethod,
  DeliveryRate,
  Digital,
  DigitalLink,
  Discount,
  Fulfillment,
  GiftCard,
  GiftCardBatch,
  Invitation,
  LineItem,
  Locale,
  Market,
  Media,
  NewsletterSubscriber,
  OptionType,
  OptionValue,
  Order,
  Payment,
  PaymentCombination,
  PaymentMethod,
  PaymentSession,
  PaymentSetupSession,
  PaymentSource,
  Policy,
  Post,
  Price,
  Product,
  Promotion,
  Refund,
  ReturnAuthorization,
  ReturnItem,
  State,
  StockLocation,
  StoreCredit,
  Variant,
  Wishlist,
  WishlistItem,
} from './generated'

// Checkout requirement — a single unsatisfied checkout prerequisite
export interface CheckoutRequirement {
  /** Checkout step this requirement belongs to (e.g. "address", "payment") */
  step: string
  /** Field that needs to be satisfied (e.g. "email", "shipping_address") */
  field: string
  /** Human-readable message describing what's needed */
  message: string
}

// CHK-P1-4 (2026-09-03): server-side CheckoutView projection —
// hand-written mirror of PallasTrade::Api::V3::Store::Checkout::CheckoutSerializer
// (OrderCheckout::CheckoutView). Flat single-resource shape, no { data } envelope.
// Read-only contract; money = major-unit decimal strings (display_* for UI).

/** Explanatory adjustment detail line (discounts/taxes). */
export interface CheckoutViewLine {
  id: string
  amount: string | null
  currency: string
}

export interface CheckoutView {
  id: string
  number: string
  state: string
  status: string
  payment_state: string | null
  shipment_state: string | null
  email: string | null
  currency: string
  submitted_at: string | null
  completed_at: string | null
  /** OrderCheckout content version (server increments on recalcs/mutations) */
  version: number
  /** Money-input fingerprint (SHA256[0..16]) — quote identity */
  price_version: string | null
  /** Quote expiry ISO8601 (null = no quote yet / legacy order) */
  expires_at: string | null
  /** Server Readiness: true when all checkout requirements are satisfied */
  ready: boolean
  /** Codes of unsatisfied requirements: contact / shipping_address / delivery_rate / balance */
  missing_requirements: string[]
  item_total: string | null
  display_item_total: string | null
  delivery_total: string | null
  display_delivery_total: string | null
  adjustment_total: string | null
  display_adjustment_total: string | null
  discount_total: string | null
  display_discount_total: string | null
  tax_total: string | null
  display_tax_total: string | null
  included_tax_total: string | null
  display_included_tax_total: string | null
  additional_tax_total: string | null
  display_additional_tax_total: string | null
  total: string | null
  display_total: string | null
  amount_due: string | null
  display_amount_due: string | null
  items: Array<LineItemType>
  fulfillments: Array<FulfillmentType>
  shipping_address: AddressType | null
  billing_address: AddressType | null
  discounts: Array<CheckoutViewLine>
  taxes: Array<CheckoutViewLine>
}

// CHK-P1-4B (2026-09-04): PATCH /orders/:id/checkout — one field set per request.
export interface CheckoutUpdateParams {
  contact?: { email: string }
  shipping_address?: AddressParams
  shipping_address_id?: string
  delivery_rate_id?: string
}

// Cart warning type — convenience alias for the inline type from the generated Cart
export type CartWarning = CartType['warnings'][number]

// Hand-written domain types
export type {
  AddressParams,
  ErrorResponse,
  ListParams,
  ListResponse,
  LocaleDefaults,
  PaginatedResponse,
  PaginationMeta,
} from '@pallastrade/sdk-core'

// Store auth types
export interface AuthTokens {
  token: string
  refresh_token: string
  user: {
    id: string
    email: string
    first_name: string | null
    last_name: string | null
  }
}

export type { EmailPasswordLogin, LoginCredentials, ProviderLogin } from '@pallastrade/sdk-core'

export interface RequestPasswordResetParams {
  email: string
  redirect_url?: string
}

export interface ResetPasswordParams {
  password: string
  password_confirmation: string
}

export interface RegisterParams {
  email: string
  password: string
  password_confirmation: string
  first_name?: string
  last_name?: string
  phone?: string
  accepts_email_marketing?: boolean
  /** Cloudflare Turnstile human-verification token (`cf-turnstile-response`). */
  turnstile_token?: string
  /** Arbitrary key-value metadata (stored, not returned in responses) */
  metadata?: Record<string, unknown>
}

export interface ProductListParams extends ListParams {
  /** Sort: 'price', '-price', 'best_selling', 'name', '-name', '-available_on', 'available_on' */
  sort?: string
  /** Full-text search across name and SKU */
  search?: string
  /** Filter: name contains */
  name_cont?: string
  /** Filter: price >= value */
  price_gte?: number
  /** Filter: price <= value */
  price_lte?: number
  /** Filter by option value prefix IDs */
  with_option_value_ids?: string[]
  /** Filter: only in-stock products */
  in_stock?: boolean
  /** Filter: only out-of-stock products */
  out_of_stock?: boolean
  /** Filter: products in category (includes descendants) */
  in_category?: string
  /** Filter: products in any of the given categories (includes descendants, OR logic) */
  in_categories?: string[]
  /** Any additional Ransack predicate */
  [key: string]: string | number | boolean | (string | number)[] | undefined
}

export interface CategoryListParams extends ListParams {
  /** Sort order, e.g. 'name', '-created_at' */
  sort?: string
  /** Filter: name contains */
  name_cont?: string
  parent_id_eq?: string | number
  depth_eq?: number
  /** Any additional Ransack predicate */
  [key: string]: string | number | boolean | (string | number)[] | undefined
}

export interface OrderListParams extends ListParams {
  /** Sort order, e.g. 'completed_at desc' */
  sort?: string
  /** Full-text search across number, email, customer name */
  search?: string
  state_eq?: string
  completed_at_gte?: string
  completed_at_lte?: string
  /** Any additional Ransack predicate */
  [key: string]: string | number | boolean | (string | number)[] | undefined
}

// Line item input for bulk cart/order operations
export interface LineItemInput {
  /** Prefixed variant ID (e.g., "variant_k5nR8xLq") */
  variant_id: string
  /** Quantity to set (defaults to 1 if omitted) */
  quantity?: number
  /** P1：勾选标记（新购物车结算范围；默认 true） */
  selected?: boolean
  /** Arbitrary key-value metadata (merged with existing on upsert) */
  metadata?: Record<string, unknown>
}

// ── 订单流程标准电商改造 P1（2026-08-30）：新购物车实体（pallastrade_carts）──
// 与 generated Cart（legacy Order 同表）不同：独立表、极简状态机、items 为 cart_items。
export interface CartItem {
  id: string
  variant_id: string
  quantity: number
  /** 勾选（本次结算范围） */
  selected: boolean
  name: string
  slug: string
  options_text: string
  currency: string
  unit_price: string | null
  display_unit_price: string | null
  amount: string | null
  display_amount: string | null
  thumbnail_url: string | null
}

export type ShoppingCartStatus = 'active' | 'converted' | 'abandoned'

export interface ShoppingCart {
  id: string
  token: string
  status: ShoppingCartStatus
  email: string | null
  customer_note: string | null
  currency: string
  locale: string | null
  item_count: number
  item_total: string | null
  display_item_total: string | null
  converted_at: string | null
  shipping_method_id: string | null
  items: CartItem[]
  billing_address: AddressType | null
  shipping_address: AddressType | null
  /** 下单链路统一化（PRD-20260830-checkout）：可选支付方式（store 前端可用） */
  payment_methods?: PaymentMethod[]
}

/** Result of the standard Cart submit command. The Order remains the top-level
 * resource for backward compatibility; a successor Cart is returned only when
 * unselected items remain or Buy Now restores a previous active Cart. */
export type CartSubmitResult = OrderType & {
  successor_cart: ShoppingCart | null
}

// Cart operations
export interface CreateCartParams {
  /** Arbitrary key-value metadata (stored, not returned in responses) */
  metadata?: Record<string, unknown>
  /** Items to add to the cart on creation */
  items?: LineItemInput[]
}

export interface AddLineItemParams {
  variant_id: string
  quantity: number
  /** Arbitrary key-value metadata (stored, not returned in responses) */
  metadata?: Record<string, unknown>
}

export interface UpdateLineItemParams {
  quantity?: number
  /** P1：新购物车行勾选状态（标准流程购物车专用） */
  selected?: boolean
  /** Arbitrary key-value metadata (merged with existing) */
  metadata?: Record<string, unknown>
}

/** P1：新购物车行更新参数（数量/勾选） */
export interface UpdateCartItemParams {
  quantity?: number
  selected?: boolean
  metadata?: Record<string, unknown>
}

export interface UpdateCartParams {
  email?: string
  currency?: string
  locale?: string
  customer_note?: string
  /** Arbitrary key-value metadata (merged with existing) */
  metadata?: Record<string, unknown>
  /** Existing address ID to use as billing address */
  billing_address_id?: string
  /** Existing address ID to use as shipping address */
  shipping_address_id?: string
  /** New billing address */
  billing_address?: AddressParams
  /** New shipping address */
  shipping_address?: AddressParams
  /** P1：订单确认阶段选择的配送方式 */
  shipping_method_id?: string
  /** When true, copies shipping address to billing address */
  use_shipping?: boolean
  /** Items to upsert (sets quantity for existing, creates new) */
  items?: LineItemInput[]
}

/**
 * 订单模块（PRD-20260829-checkout 收货信息独立填写）：
 * 更新已下单未支付订单的收货地址（PATCH /customers/me/orders/:id/shipping_address）。
 * 二选一：shipping_address_id 引用用户已存地址，或 shipping_address 就地更新/新建。
 */
export interface UpdateOrderShippingAddressParams {
  /** Existing address ID (must belong to the current user) */
  shipping_address_id?: string
  /** New/inline shipping address */
  shipping_address?: AddressParams
}

// Payments
export interface CreatePaymentParams {
  payment_method_id: string
  amount?: string
  metadata?: Record<string, unknown>
}

// Payment Sessions
export interface CreatePaymentSessionParams {
  payment_method_id: string
  amount?: string
  external_data?: Record<string, unknown>
}

// Payment Combinations (P5, 2026-08-27): 合并支付
// POST /api/v3/store/payment_combinations
// PALLAS-CUSTOM (2026-08-29, bugfix): payment_method_id 可选——服务端缺省选默认会话类支付方式。
export interface CreatePaymentCombinationParams {
  /** Prefixed order IDs (e.g. order_…) to combine into a single payment */
  order_ids: string[]
  /** Optional payment method (defaults to the store's session-based method server-side) */
  payment_method_id?: string
}

export interface UpdatePaymentSessionParams {
  amount?: string
  external_data?: Record<string, unknown>
}

export interface CompletePaymentSessionParams {
  session_result?: string
  external_data?: Record<string, unknown>
}

// Payment Setup Sessions
export interface CreatePaymentSetupSessionParams {
  payment_method_id: string
  external_data?: Record<string, unknown>
}

export interface CompletePaymentSetupSessionParams {
  external_data?: Record<string, unknown>
}

// Product Filters types
export interface FilterOption {
  id: string
  count: number
}

export interface OptionFilterOption extends FilterOption {
  name: string
  label: string
  position: number
  color_code: string | null
  image_url: string | null
}

export interface CategoryFilterOption {
  id: string
  name: string
  permalink: string
  count: number
}

export interface PriceRangeFilter {
  id: 'price'
  type: 'price_range'
  min: number
  max: number
  currency: string
}

export interface AvailabilityFilter {
  id: 'availability'
  type: 'availability'
  options: FilterOption[]
}

export interface OptionFilter {
  id: string
  type: 'option'
  name: string
  label: string
  kind: string
  options: OptionFilterOption[]
}

export interface CategoryFilter {
  id: 'categories'
  type: 'category'
  options: CategoryFilterOption[]
}

export type ProductFilter = PriceRangeFilter | AvailabilityFilter | OptionFilter | CategoryFilter

export interface SortOption {
  id: string
}

export interface ProductFiltersResponse {
  filters: ProductFilter[]
  sort_options: SortOption[]
  default_sort: string
  total_count: number
}

export interface ProductFiltersParams {
  category_id?: string
  q?: Record<string, unknown>
}
