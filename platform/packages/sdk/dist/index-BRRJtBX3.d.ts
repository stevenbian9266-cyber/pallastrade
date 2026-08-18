interface LocaleDefaults {
  locale?: string
  currency?: string
  country?: string
  /** Channel code (e.g., 'pos', 'wholesale') sent as X-PallasTrade-Channel */
  channel?: string
}
interface PaginationMeta {
  page: number
  limit: number
  count: number
  pages: number
  from: number
  to: number
  in: number
  previous: number | null
  next: number | null
}
interface ListResponse<T> {
  data: T[]
}
interface PaginatedResponse<T> extends ListResponse<T> {
  meta: PaginationMeta
}
interface ErrorResponse {
  error: {
    code: string
    message: string
    details?: Record<string, string[]>
  }
}
interface ListParams {
  page?: number
  limit?: number
  /** Sort order. Prefix with - for descending, e.g. '-created_at', 'name'. Comma-separated for multiple fields. */
  sort?: string
  /** Associations to expand. Supports dot notation for nested expand (max 4 levels), e.g. ['variants', 'variants.media'] */
  expand?: string[]
  /** Fields to include in response, e.g. ['name', 'slug', 'price']. Omit to return all fields. 'id' is always included. */
  fields?: string[]
}
interface AddressParams {
  first_name: string
  last_name: string
  address1: string
  address2?: string
  city: string
  postal_code: string
  phone?: string
  company?: string
  /** ISO 3166-1 alpha-2 country code (e.g., "US", "DE") */
  country_iso: string
  /** ISO 3166-2 subdivision code without country prefix (e.g., "CA", "NY") */
  state_abbr?: string
  /** State name - used for countries without predefined states */
  state_name?: string
  /** When true, relaxes validation requirements (name, phone, postal_code, street) */
  quick_checkout?: boolean
  /** Set as default billing address */
  is_default_billing?: boolean
  /** Set as default shipping address */
  is_default_shipping?: boolean
}
/**
 * Built-in email/password login. The default when `provider` is omitted.
 */
interface EmailPasswordLogin {
  provider?: 'email'
  email: string
  password: string
}
/**
 * Provider-dispatched login. The `provider` field selects a strategy registered
 * server-side in `PallasTrade.store_authentication_strategies` (or `admin_authentication_strategies`).
 * Additional fields are forwarded to the strategy's `authenticate` method — consult its
 * documentation for the required shape (e.g. `{ provider: 'auth0', token: '<jwt>' }`).
 */
interface ProviderLogin {
  provider: string
  [key: string]: unknown
}
type LoginCredentials = EmailPasswordLogin | ProviderLogin

interface RetryConfig {
  /** Maximum number of retries (default: 2) */
  maxRetries?: number
  /** HTTP status codes to retry on (default: [429, 500, 502, 503, 504]) */
  retryOnStatus?: number[]
  /** Base delay in ms for exponential backoff (default: 300) */
  baseDelay?: number
  /** Maximum delay in ms (default: 10000) */
  maxDelay?: number
  /** Whether to retry on network errors (default: true) */
  retryOnNetworkError?: boolean
}
interface RequestOptions {
  /** Bearer token for authenticated requests */
  token?: string
  /** PallasTrade token for guest cart/checkout/order access */
  guestToken?: string
  /** Locale for translated content (e.g., 'en', 'fr') */
  locale?: string
  /** Currency for prices (e.g., 'USD', 'EUR') */
  currency?: string
  /** Country ISO code for market resolution (e.g., 'US', 'DE') */
  country?: string
  /** Channel code (e.g., 'pos', 'wholesale') sent as X-PallasTrade-Channel — selects which sales channel scopes the request */
  channel?: string
  /** Idempotency key for safe retries of mutating requests (max 255 characters) */
  idempotencyKey?: string
  /** Custom headers */
  headers?: Record<string, string>
}
interface InternalRequestOptions extends RequestOptions {
  body?: unknown
  params?: Record<string, string | number | boolean | (string | number)[] | undefined>
}
declare class PallasTradeError extends Error {
  readonly code: string
  readonly status: number
  readonly details?: Record<string, string[]>
  constructor(response: ErrorResponse, status: number)
}
type RequestFn = <T>(
  method: string,
  path: string,
  options?: InternalRequestOptions,
) => Promise<T>

interface Address {
    id: string;
    first_name: string | null;
    last_name: string | null;
    full_name: string;
    address1: string | null;
    address2: string | null;
    postal_code: string | null;
    city: string | null;
    phone: string | null;
    company: string | null;
    country_name: string;
    country_iso: string;
    state_text: string | null;
    state_abbr: string | null;
    quick_checkout: boolean;
    is_default_billing: boolean;
    is_default_shipping: boolean;
    state_name: string | null;
}

interface Base {
    id: string;
}

interface Cart {
    id: string;
    market_id: string | null;
    number: string;
    token: string;
    email: string | null;
    customer_note: string | null;
    currency: string;
    locale: string | null;
    total_quantity: number;
    warnings: Array<{
        code: string;
        message: string;
        line_item_id?: string;
        variant_id?: string;
    }>;
    item_total: string | null;
    display_item_total: string | null;
    adjustment_total: string | null;
    display_adjustment_total: string | null;
    discount_total: string | null;
    display_discount_total: string | null;
    tax_total: string | null;
    display_tax_total: string | null;
    included_tax_total: string | null;
    display_included_tax_total: string | null;
    additional_tax_total: string | null;
    display_additional_tax_total: string | null;
    total: string | null;
    display_total: string | null;
    gift_card_total: string | null;
    display_gift_card_total: string | null;
    amount_due: string | null;
    display_amount_due: string | null;
    delivery_total: string | null;
    display_delivery_total: string | null;
    store_credit_total: string | null;
    display_store_credit_total: string | null;
    covered_by_store_credit: boolean;
    current_step: string;
    completed_steps: Array<string>;
    requirements: Array<{
        step: string;
        field: string;
        message: string;
    }>;
    shipping_eq_billing_address: boolean;
    discounts: Array<Discount>;
    items: Array<LineItem>;
    fulfillments: Array<Fulfillment>;
    payments: Array<Payment>;
    billing_address: Address | null;
    shipping_address: Address | null;
    payment_methods: Array<PaymentMethod>;
    gift_card: GiftCard | null;
    market: Market | null;
}

interface Category {
    id: string;
    name: string;
    permalink: string;
    position: number;
    depth: number;
    meta_title: string | null;
    meta_description: string | null;
    meta_keywords: string | null;
    children_count: number;
    parent_id: string | null;
    description: string;
    description_html: string;
    image_url: string | null;
    square_image_url: string | null;
    is_root: boolean;
    is_child: boolean;
    is_leaf: boolean;
    parent?: Category;
    children?: Array<Category>;
    ancestors?: Array<Category>;
    custom_fields?: Array<CustomField>;
}

interface Country {
    iso: string;
    iso3: string;
    name: string;
    states_required: boolean;
    zipcode_required: boolean;
    states?: Array<State>;
    market?: Market | null;
}

interface CreditCard {
    id: string;
    brand: string;
    last4: string;
    month: number;
    year: number;
    name: string | null;
    default: boolean;
    gateway_payment_profile_id: string | null;
}

interface Currency {
    iso_code: string;
    name: string;
    symbol: string;
}

interface CustomField {
    id: string;
    label: string;
    /** @deprecated Use `field_type` instead. The legacy `type` field returns the Ruby STI class name (e.g. `PallasTrade::Metafields::ShortText`) and will be removed in a future minor. */
    type: string;
    field_type: 'short_text' | 'long_text' | 'rich_text' | 'number' | 'boolean' | 'json';
    key: string;
    value: any;
}

interface Customer {
    id: string;
    email: string;
    first_name: string | null;
    last_name: string | null;
    phone: string | null;
    accepts_email_marketing: boolean;
    full_name: string;
    available_store_credit_total: string;
    display_available_store_credit_total: string;
    addresses: Array<Address>;
    default_billing_address: Address | null;
    default_shipping_address: Address | null;
    newsletter_subscriber: NewsletterSubscriber | null;
}

interface DeliveryMethod {
    id: string;
    name: string;
    code: string | null;
}

interface DeliveryRate {
    id: string;
    delivery_method_id: string;
    name: string;
    selected: boolean;
    cost: string;
    total: string;
    additional_tax_total: string;
    included_tax_total: string;
    tax_total: string;
    display_cost: string;
    display_total: string;
    display_additional_tax_total: string;
    display_included_tax_total: string;
    display_tax_total: string;
    delivery_method: DeliveryMethod;
}

interface DigitalLink {
    id: string;
    access_counter: number;
    filename: string;
    content_type: string;
    download_url: string;
    authorizable: boolean;
    expired: boolean;
    access_limit_exceeded: boolean;
}

interface Digital {
    id: string;
    created_at: string;
    updated_at: string;
    variant_id: string | null;
}

interface Discount {
    id: string;
    promotion_id: string;
    name: string;
    description: string | null;
    code: string | null;
    amount: string | null;
    display_amount: string | null;
}

interface Fulfillment {
    id: string;
    number: string;
    tracking: string | null;
    tracking_url: string | null;
    cost: string | null;
    display_cost: string | null;
    total: string | null;
    display_total: string | null;
    discount_total: string | null;
    display_discount_total: string | null;
    additional_tax_total: string | null;
    display_additional_tax_total: string | null;
    included_tax_total: string | null;
    display_included_tax_total: string | null;
    tax_total: string | null;
    display_tax_total: string | null;
    status: string;
    fulfillment_type: string;
    fulfilled_at: string | null;
    items: Array<{
        item_id: string;
        variant_id: string;
        quantity: number;
    }>;
    delivery_method: DeliveryMethod;
    stock_location: StockLocation;
    delivery_rates: Array<DeliveryRate>;
}

interface GiftCardBatch {
    id: string;
    codes_count: number;
    currency: string | null;
    prefix: string | null;
    created_at: string;
    updated_at: string;
    amount: string | null;
    expires_at: string | null;
    created_by_id: string | null;
}

interface GiftCard {
    id: string;
    code: string;
    status: string;
    currency: string;
    amount: string | null;
    amount_used: string | null;
    amount_authorized: string | null;
    amount_remaining: string | null;
    display_amount: string | null;
    display_amount_used: string | null;
    display_amount_remaining: string | null;
    expires_at: string | null;
    redeemed_at: string | null;
    expired: boolean;
    active: boolean;
}

interface Invitation {
    id: string;
    email: string;
    resource_type: string | null;
    inviter_type: string | null;
    invitee_type: string | null;
    created_at: string;
    updated_at: string;
    status: string;
    resource_id: string | null;
    inviter_id: string | null;
    invitee_id: string | null;
    role_id: string | null;
    expires_at: string | null;
    accepted_at: string | null;
}

interface LineItem {
    id: string;
    variant_id: string;
    preorder: boolean;
    preorder_ships_at: string | null;
    quantity: number;
    currency: string;
    name: string;
    slug: string;
    options_text: string;
    price: string | null;
    display_price: string | null;
    total: string | null;
    display_total: string | null;
    adjustment_total: string | null;
    display_adjustment_total: string | null;
    additional_tax_total: string | null;
    display_additional_tax_total: string | null;
    included_tax_total: string | null;
    display_included_tax_total: string | null;
    discount_total: string | null;
    display_discount_total: string | null;
    pre_tax_amount: string | null;
    display_pre_tax_amount: string | null;
    discounted_amount: string | null;
    display_discounted_amount: string | null;
    display_compare_at_amount: string | null;
    compare_at_amount: string | null;
    thumbnail_url: string | null;
    option_values: Array<OptionValue>;
    digital_links: Array<DigitalLink>;
}

interface Locale {
    code: string;
    name: string;
    default: boolean;
    rtl: boolean;
}

interface Market {
    id: string;
    name: string;
    currency: string;
    default_locale: string;
    tax_inclusive: boolean;
    default: boolean;
    country_isos: Array<string>;
    supported_locales: Array<string>;
    countries?: Array<Country>;
}

interface Media {
    id: string;
    product_id: string | null;
    variant_ids: Array<string>;
    position: number;
    alt: string | null;
    media_type: string;
    focal_point_x: number | null;
    focal_point_y: number | null;
    external_video_url: string | null;
    original_url: string | null;
    mini_url: string | null;
    small_url: string | null;
    medium_url: string | null;
    large_url: string | null;
    xlarge_url: string | null;
    og_image_url: string | null;
}

interface NewsletterSubscriber {
    id: string;
    email: string;
    created_at: string;
    updated_at: string;
    verified: boolean;
    verified_at: string | null;
    customer_id: string | null;
}

interface OptionType {
    id: string;
    name: string;
    label: string;
    position: number;
    kind: string;
}

interface OptionValue {
    id: string;
    option_type_id: string;
    name: string;
    label: string;
    position: number;
    color_code: string | null;
    option_type_name: string;
    option_type_label: string;
    image_url: string | null;
}

interface Order {
    id: string;
    market_id: string | null;
    channel_id: string | null;
    number: string;
    email: string;
    customer_note: string | null;
    currency: string;
    locale: string | null;
    total_quantity: number;
    fulfillment_status: string | null;
    payment_status: string | null;
    completed_at: string | null;
    item_total: string | null;
    display_item_total: string | null;
    adjustment_total: string | null;
    display_adjustment_total: string | null;
    discount_total: string | null;
    display_discount_total: string | null;
    tax_total: string | null;
    display_tax_total: string | null;
    included_tax_total: string | null;
    display_included_tax_total: string | null;
    additional_tax_total: string | null;
    display_additional_tax_total: string | null;
    total: string | null;
    display_total: string | null;
    gift_card_total: string | null;
    display_gift_card_total: string | null;
    amount_due: string | null;
    display_amount_due: string | null;
    delivery_total: string | null;
    display_delivery_total: string | null;
    store_credit_total: string | null;
    display_store_credit_total: string | null;
    covered_by_store_credit: boolean;
    discounts: Array<Discount>;
    items: Array<LineItem>;
    fulfillments: Array<Fulfillment>;
    payments: Array<Payment>;
    billing_address: Address | null;
    shipping_address: Address | null;
    gift_card: GiftCard | null;
    market: Market | null;
}

interface PaymentMethod {
    id: string;
    name: string;
    description: string | null;
    type: string;
    session_required: boolean;
    source_required: boolean;
}

interface Payment {
    id: string;
    payment_method_id: string;
    response_code: string | null;
    number: string;
    amount: string | null;
    display_amount: string | null;
    status: string;
    source_type: 'credit_card' | 'store_credit' | 'payment_source' | null;
    source_id: string | null;
    source: CreditCard | StoreCredit | PaymentSource | null;
    payment_method: PaymentMethod;
}

interface PaymentSession {
    id: string;
    status: string;
    currency: string;
    external_id: string;
    external_data: Record<string, unknown>;
    customer_external_id: string | null;
    expires_at: string | null;
    amount: string;
    payment_method_id: string;
    order_id: string;
    payment_method: PaymentMethod;
    payment?: Payment;
}

interface PaymentSetupSession {
    id: string;
    status: string;
    external_id: string | null;
    external_client_secret: string | null;
    external_data: Record<string, unknown>;
    payment_method_id: string | null;
    payment_source_id: string | null;
    payment_source_type: string | null;
    customer_id: string | null;
    payment_method: PaymentMethod;
}

interface PaymentSource {
    id: string;
    gateway_payment_profile_id: string | null;
}

interface Policy {
    id: string;
    name: string;
    slug: string;
    body: string | null;
    body_html: string | null;
}

interface Post {
    id: string;
    title: string;
    slug: string;
    excerpt: string | null;
    author: string | null;
    published_at: string | null;
    cover_image_url: string | null;
    body: string | null;
    body_html: string | null;
    seo_title: string | null;
    seo_description: string | null;
}

interface PriceHistory {
    id: string;
    amount: string;
    amount_in_cents: number;
    currency: string;
    display_amount: string;
    recorded_at: string;
}

interface Price {
    id: string;
    amount: string | null;
    amount_in_cents: number | null;
    compare_at_amount: string | null;
    compare_at_amount_in_cents: number | null;
    currency: string | null;
    display_amount: string | null;
    display_compare_at_amount: string | null;
    price_list_id: string | null;
}

interface Product {
    id: string;
    name: string;
    slug: string;
    meta_title: string | null;
    meta_description: string | null;
    meta_keywords: string | null;
    variant_count: number;
    available_on: string | null;
    preorder_ships_at: string | null;
    purchasable: boolean;
    preorder: boolean;
    in_stock: boolean;
    backorderable: boolean;
    available: boolean;
    description: string | null;
    description_html: string | null;
    default_variant_id: string;
    thumbnail_url: string | null;
    tags: Array<string>;
    average_rating: number | null;
    review_count: number;
    price: Price;
    original_price: Price | null;
    primary_media?: Media;
    media?: Array<Media>;
    variants?: Array<Variant>;
    default_variant?: Variant;
    option_types?: Array<OptionType>;
    option_values?: Array<OptionValue>;
    categories?: Array<Category>;
    custom_fields?: Array<CustomField>;
    prior_price?: PriceHistory | null;
}

interface Promotion {
    id: string;
    name: string;
    description: string | null;
    code: string | null;
}

interface Refund {
    id: string;
    transaction_id: string | null;
    amount: string | null;
    payment_id: string | null;
    refund_reason_id: string | null;
    reimbursement_id: string | null;
}

interface ReturnAuthorization {
    id: string;
    number: string;
    status: string;
    order_id: string | null;
    stock_location_id: string | null;
    return_authorization_reason_id: string | null;
}

interface ReturnItem {
    id: string;
    reception_status: string | null;
    acceptance_status: string | null;
    created_at: string;
    updated_at: string;
    pre_tax_amount: string | null;
    included_tax_total: string | null;
    additional_tax_total: string | null;
    inventory_unit_id: string | null;
    return_authorization_id: string | null;
    customer_return_id: string | null;
    reimbursement_id: string | null;
    exchange_variant_id: string | null;
}

interface State {
    abbr: string;
    name: string;
}

interface StockLocation {
    id: string;
    state_abbr: string | null;
    name: string;
    address1: string | null;
    city: string | null;
    zipcode: string | null;
    country_iso: string | null;
    country_name: string | null;
    state_text: string | null;
}

interface StoreCredit {
    id: string;
    amount: string;
    amount_used: string;
    amount_remaining: string;
    display_amount: string;
    display_amount_used: string;
    display_amount_remaining: string;
    currency: string;
}

interface Variant {
    id: string;
    product_id: string;
    sku: string | null;
    options_text: string;
    track_inventory: boolean;
    media_count: number;
    preorder_ships_at: string | null;
    thumbnail_url: string | null;
    purchasable: boolean;
    in_stock: boolean;
    backorderable: boolean;
    preorder: boolean;
    weight: number | null;
    height: number | null;
    width: number | null;
    depth: number | null;
    price: Price;
    original_price: Price | null;
    primary_media?: Media;
    media?: Array<Media>;
    option_values: Array<OptionValue>;
    custom_fields?: Array<CustomField>;
    prior_price?: PriceHistory | null;
}

interface WishlistItem {
    id: string;
    variant_id: string;
    wishlist_id: string;
    quantity: number;
    variant: Variant;
}

interface Wishlist {
    id: string;
    name: string;
    token: string;
    is_default: boolean;
    is_private: boolean;
    items?: Array<WishlistItem>;
}

interface CheckoutRequirement {
    /** Checkout step this requirement belongs to (e.g. "address", "payment") */
    step: string;
    /** Field that needs to be satisfied (e.g. "email", "shipping_address") */
    field: string;
    /** Human-readable message describing what's needed */
    message: string;
}
type CartWarning = Cart['warnings'][number];

interface AuthTokens {
    token: string;
    refresh_token: string;
    user: {
        id: string;
        email: string;
        first_name: string | null;
        last_name: string | null;
    };
}

interface RequestPasswordResetParams {
    email: string;
    redirect_url?: string;
}
interface ResetPasswordParams {
    password: string;
    password_confirmation: string;
}
interface RegisterParams {
    email: string;
    password: string;
    password_confirmation: string;
    first_name?: string;
    last_name?: string;
    phone?: string;
    accepts_email_marketing?: boolean;
    /** Cloudflare Turnstile human-verification token (`cf-turnstile-response`). */
    turnstile_token?: string;
    /** Arbitrary key-value metadata (stored, not returned in responses) */
    metadata?: Record<string, unknown>;
}
interface ProductListParams extends ListParams {
    /** Sort: 'price', '-price', 'best_selling', 'name', '-name', '-available_on', 'available_on' */
    sort?: string;
    /** Full-text search across name and SKU */
    search?: string;
    /** Filter: name contains */
    name_cont?: string;
    /** Filter: price >= value */
    price_gte?: number;
    /** Filter: price <= value */
    price_lte?: number;
    /** Filter by option value prefix IDs */
    with_option_value_ids?: string[];
    /** Filter: only in-stock products */
    in_stock?: boolean;
    /** Filter: only out-of-stock products */
    out_of_stock?: boolean;
    /** Filter: products in category (includes descendants) */
    in_category?: string;
    /** Filter: products in any of the given categories (includes descendants, OR logic) */
    in_categories?: string[];
    /** Any additional Ransack predicate */
    [key: string]: string | number | boolean | (string | number)[] | undefined;
}
interface CategoryListParams extends ListParams {
    /** Sort order, e.g. 'name', '-created_at' */
    sort?: string;
    /** Filter: name contains */
    name_cont?: string;
    parent_id_eq?: string | number;
    depth_eq?: number;
    /** Any additional Ransack predicate */
    [key: string]: string | number | boolean | (string | number)[] | undefined;
}
interface OrderListParams extends ListParams {
    /** Sort order, e.g. 'completed_at desc' */
    sort?: string;
    /** Full-text search across number, email, customer name */
    search?: string;
    state_eq?: string;
    completed_at_gte?: string;
    completed_at_lte?: string;
    /** Any additional Ransack predicate */
    [key: string]: string | number | boolean | (string | number)[] | undefined;
}
interface LineItemInput {
    /** Prefixed variant ID (e.g., "variant_k5nR8xLq") */
    variant_id: string;
    /** Quantity to set (defaults to 1 if omitted) */
    quantity?: number;
    /** Arbitrary key-value metadata (merged with existing on upsert) */
    metadata?: Record<string, unknown>;
}
interface CreateCartParams {
    /** Arbitrary key-value metadata (stored, not returned in responses) */
    metadata?: Record<string, unknown>;
    /** Items to add to the cart on creation */
    items?: LineItemInput[];
}
interface AddLineItemParams {
    variant_id: string;
    quantity: number;
    /** Arbitrary key-value metadata (stored, not returned in responses) */
    metadata?: Record<string, unknown>;
}
interface UpdateLineItemParams {
    quantity?: number;
    /** Arbitrary key-value metadata (merged with existing) */
    metadata?: Record<string, unknown>;
}
interface UpdateCartParams {
    email?: string;
    currency?: string;
    locale?: string;
    customer_note?: string;
    /** Arbitrary key-value metadata (merged with existing) */
    metadata?: Record<string, unknown>;
    /** Existing address ID to use as billing address */
    billing_address_id?: string;
    /** Existing address ID to use as shipping address */
    shipping_address_id?: string;
    /** New billing address */
    billing_address?: AddressParams;
    /** New shipping address */
    shipping_address?: AddressParams;
    /** When true, copies shipping address to billing address */
    use_shipping?: boolean;
    /** Items to upsert (sets quantity for existing, creates new) */
    items?: LineItemInput[];
}
interface CreatePaymentParams {
    payment_method_id: string;
    amount?: string;
    metadata?: Record<string, unknown>;
}
interface CreatePaymentSessionParams {
    payment_method_id: string;
    amount?: string;
    external_data?: Record<string, unknown>;
}
interface UpdatePaymentSessionParams {
    amount?: string;
    external_data?: Record<string, unknown>;
}
interface CompletePaymentSessionParams {
    session_result?: string;
    external_data?: Record<string, unknown>;
}
interface CreatePaymentSetupSessionParams {
    payment_method_id: string;
    external_data?: Record<string, unknown>;
}
interface CompletePaymentSetupSessionParams {
    external_data?: Record<string, unknown>;
}
interface FilterOption {
    id: string;
    count: number;
}
interface OptionFilterOption extends FilterOption {
    name: string;
    label: string;
    position: number;
    color_code: string | null;
    image_url: string | null;
}
interface CategoryFilterOption {
    id: string;
    name: string;
    permalink: string;
    count: number;
}
interface PriceRangeFilter {
    id: 'price';
    type: 'price_range';
    min: number;
    max: number;
    currency: string;
}
interface AvailabilityFilter {
    id: 'availability';
    type: 'availability';
    options: FilterOption[];
}
interface OptionFilter {
    id: string;
    type: 'option';
    name: string;
    label: string;
    kind: string;
    options: OptionFilterOption[];
}
interface CategoryFilter {
    id: 'categories';
    type: 'category';
    options: CategoryFilterOption[];
}
type ProductFilter = PriceRangeFilter | AvailabilityFilter | OptionFilter | CategoryFilter;
interface SortOption {
    id: string;
}
interface ProductFiltersResponse {
    filters: ProductFilter[];
    sort_options: SortOption[];
    default_sort: string;
    total_count: number;
}
interface ProductFiltersParams {
    category_id?: string;
    q?: Record<string, unknown>;
}

export { type CheckoutRequirement as $, type AuthTokens as A, type AddressParams as B, type CategoryListParams as C, type CreditCard as D, type OrderListParams as E, type CreatePaymentSetupSessionParams as F, type GiftCard as G, type PaymentSetupSession as H, type CompletePaymentSetupSessionParams as I, type RequestPasswordResetParams as J, type ResetPasswordParams as K, type LoginCredentials as L, type Market as M, type NewsletterSubscriber as N, type Order as O, type ProductListParams as P, type WishlistItem as Q, type RequestFn as R, type StoreCredit as S, type RetryConfig as T, type UpdateCartParams as U, type AvailabilityFilter as V, type Wishlist as W, type Base as X, type CartWarning as Y, type CategoryFilter as Z, type CategoryFilterOption as _, type RequestOptions as a, type CustomField as a0, type DeliveryMethod as a1, type DeliveryRate as a2, type Digital as a3, type DigitalLink as a4, type Discount as a5, type EmailPasswordLogin as a6, type ErrorResponse as a7, type FilterOption as a8, type Fulfillment as a9, type GiftCardBatch as aa, type Invitation as ab, type LineItem as ac, type LineItemInput as ad, type LocaleDefaults as ae, type Media as af, type OptionFilter as ag, type OptionFilterOption as ah, type OptionType as ai, type OptionValue as aj, type PaginationMeta as ak, PallasTradeError as al, type PaymentMethod as am, type PaymentSource as an, type Price as ao, type PriceRangeFilter as ap, type ProductFilter as aq, type Promotion as ar, type ProviderLogin as as, type Refund as at, type ReturnAuthorization as au, type ReturnItem as av, type SortOption as aw, type State as ax, type StockLocation as ay, type Variant as az, type PaginatedResponse as b, type Product as c, type ProductFiltersParams as d, type ProductFiltersResponse as e, type Category as f, type ListResponse as g, type Country as h, type Currency as i, type Locale as j, type Policy as k, type ListParams as l, type Post as m, type Cart as n, type CreateCartParams as o, type AddLineItemParams as p, type UpdateLineItemParams as q, type CreatePaymentParams as r, type Payment as s, type CreatePaymentSessionParams as t, type PaymentSession as u, type UpdatePaymentSessionParams as v, type CompletePaymentSessionParams as w, type RegisterParams as x, type Customer as y, type Address as z };
