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
interface RequestConfig {
  baseUrl: string
  fetchFn: typeof fetch
  retryConfig: Required<RetryConfig> | false
  /**
   * Credentials mode for cross-origin requests. Pass `'include'` for cookie-based auth.
   * Defaults to fetch's built-in default (`'same-origin'` in browsers) when omitted.
   */
  credentials?: RequestCredentials
}
interface AuthConfig {
  headerName: string
  headerValue: string
}
/**
 * Creates a bound request function for a specific API scope (store or admin).
 */
declare function createRequestFn(
  config: RequestConfig,
  basePath: string,
  auth: AuthConfig,
  defaults?: LocaleDefaults,
): RequestFn

/** Serialize expand/fields arrays into comma-separated query params */
declare function getParams(params?: {
  expand?: string[]
  fields?: string[]
}): Record<string, string> | undefined
/** Resolve retry config with defaults */
interface ResolvedRetryConfig {
  maxRetries: number
  retryOnStatus: number[]
  baseDelay: number
  maxDelay: number
  retryOnNetworkError: boolean
}
declare function resolveRetryConfig(
  retry?: RetryConfig | false,
): ResolvedRetryConfig | false

type ParamValue = string | number | boolean | (string | number)[] | undefined
/**
 * Transforms flat SDK params into Ransack-compatible query params.
 *
 * - `page`, `limit`, `expand`, `sort` pass through unchanged
 * - Keys already in `q[...]` format pass through (backward compat)
 * - All other keys are wrapped: `name_cont` → `q[name_cont]`
 */
declare function transformListParams(
  params: Record<string, unknown>,
): Record<string, ParamValue>

export { type AddressParams, type AuthConfig, type EmailPasswordLogin, type ErrorResponse, type InternalRequestOptions, type ListParams, type ListResponse, type LocaleDefaults, type LoginCredentials, type PaginatedResponse, type PaginationMeta, PallasTradeError, type ProviderLogin, type RequestConfig, type RequestFn, type RequestOptions, type ResolvedRetryConfig, type RetryConfig, createRequestFn, getParams, resolveRetryConfig, transformListParams };
