import type { ErrorResponse, LocaleDefaults } from './types'
export interface RetryConfig {
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
export interface RequestOptions {
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
export interface InternalRequestOptions extends RequestOptions {
  body?: unknown
  params?: Record<string, string | number | boolean | (string | number)[] | undefined>
}
export declare class PallasTradeError extends Error {
  readonly code: string
  readonly status: number
  readonly details?: Record<string, string[]>
  constructor(response: ErrorResponse, status: number)
}
export type RequestFn = <T>(
  method: string,
  path: string,
  options?: InternalRequestOptions,
) => Promise<T>
export interface RequestConfig {
  baseUrl: string
  fetchFn: typeof fetch
  retryConfig: Required<RetryConfig> | false
  /**
   * Credentials mode for cross-origin requests. Pass `'include'` for cookie-based auth.
   * Defaults to fetch's built-in default (`'same-origin'` in browsers) when omitted.
   */
  credentials?: RequestCredentials
}
export interface AuthConfig {
  headerName: string
  headerValue: string
}
/**
 * Creates a bound request function for a specific API scope (store or admin).
 */
export declare function createRequestFn(
  config: RequestConfig,
  basePath: string,
  auth: AuthConfig,
  defaults?: LocaleDefaults,
): RequestFn
//# sourceMappingURL=request.d.ts.map
