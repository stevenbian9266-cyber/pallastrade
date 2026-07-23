export class PallasTradeError extends Error {
  code
  status
  details
  constructor(response, status) {
    super(response.error.message)
    this.name = 'PallasTradeError'
    this.code = response.error.code
    this.status = status
    this.details = response.error.details
  }
}
function calculateDelay(attempt, config) {
  const exponentialDelay = config.baseDelay * 2 ** attempt
  const jitter = Math.random() * config.baseDelay
  return Math.min(exponentialDelay + jitter, config.maxDelay)
}
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
function generateIdempotencyKey() {
  return `pallastrade-sdk-retry-${crypto.randomUUID()}`
}
function shouldRetryOnStatus(method, status, config, hasIdempotencyKey) {
  const isIdempotent = method === 'GET' || method === 'HEAD' || hasIdempotencyKey
  if (isIdempotent) {
    return config.retryOnStatus.includes(status)
  }
  return status === 429
}
function shouldRetryOnNetworkError(method, config, hasIdempotencyKey) {
  if (!config.retryOnNetworkError) return false
  return method === 'GET' || method === 'HEAD' || hasIdempotencyKey
}
/**
 * Creates a bound request function for a specific API scope (store or admin).
 */
export function createRequestFn(config, basePath, auth, defaults) {
  return async function request(method, path, options = {}) {
    const { token, guestToken, idempotencyKey, headers = {}, body, params } = options
    // Per-request options override client-level defaults
    const locale = options.locale ?? defaults?.locale
    const currency = options.currency ?? defaults?.currency
    const country = options.country ?? defaults?.country
    const channel = options.channel ?? defaults?.channel
    // Build URL with query params.
    // `new URL(path)` throws on a relative path. When baseUrl is empty (browser
    // hitting a same-origin proxy like Vite dev), resolve against window.location.
    const browserOrigin = typeof window !== 'undefined' ? window.location.origin : undefined
    const urlBase = config.baseUrl || browserOrigin
    if (!urlBase) {
      throw new TypeError(
        'sdk-core: baseUrl is required in non-browser environments (no window.location to resolve relative URLs against)',
      )
    }
    const url = new URL(`${config.baseUrl}${basePath}${path}`, urlBase)
    if (params) {
      Object.entries(params).forEach(([key, value]) => {
        if (value !== undefined) {
          if (Array.isArray(value)) {
            for (const v of value) {
              url.searchParams.append(key, String(v))
            }
          } else {
            url.searchParams.set(key, String(value))
          }
        }
      })
    }
    // Build headers
    const requestHeaders = {
      'Content-Type': 'application/json',
      ...headers,
    }
    if (auth.headerName && auth.headerValue) {
      requestHeaders[auth.headerName] = auth.headerValue
    }
    if (token) {
      requestHeaders.Authorization = `Bearer ${token}`
    }
    if (guestToken) {
      requestHeaders['x-pallastrade-token'] = guestToken
    }
    if (locale) {
      requestHeaders['x-pallastrade-locale'] = locale
    }
    if (currency) {
      requestHeaders['x-pallastrade-currency'] = currency
    }
    if (country) {
      requestHeaders['x-pallastrade-country'] = country
    }
    if (channel) {
      requestHeaders['x-pallastrade-channel'] = channel
    }
    // Auto-generate idempotency key for mutating requests when retries are enabled (Stripe-style).
    // User-supplied keys take precedence over auto-generated ones.
    const isMutating = method !== 'GET' && method !== 'HEAD'
    const effectiveIdempotencyKey =
      idempotencyKey ?? (isMutating && config.retryConfig ? generateIdempotencyKey() : undefined)
    if (effectiveIdempotencyKey) {
      requestHeaders['Idempotency-Key'] = effectiveIdempotencyKey
    }
    const hasIdempotencyKey = !!effectiveIdempotencyKey
    const maxAttempts = config.retryConfig ? config.retryConfig.maxRetries + 1 : 1
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        const response = await config.fetchFn(url.toString(), {
          method,
          headers: requestHeaders,
          body: body ? JSON.stringify(body) : undefined,
          credentials: config.credentials,
        })
        if (!response.ok) {
          const isLastAttempt = attempt >= maxAttempts - 1
          if (
            !isLastAttempt &&
            config.retryConfig &&
            shouldRetryOnStatus(method, response.status, config.retryConfig, hasIdempotencyKey)
          ) {
            const retryAfter = response.headers.get('Retry-After')
            const delay = retryAfter
              ? Math.min(parseInt(retryAfter, 10) * 1000, config.retryConfig.maxDelay)
              : calculateDelay(attempt, config.retryConfig)
            await sleep(delay)
            continue
          }
          const errorBody = await response.json()
          throw new PallasTradeError(errorBody, response.status)
        }
        // Handle 204 No Content (empty body)
        if (response.status === 204) {
          return undefined
        }
        // Handle 202 Accepted — may or may not have a body
        if (response.status === 202) {
          const contentType = response.headers.get('content-type')
          if (contentType?.includes('application/json')) {
            return response.json()
          }
          return undefined
        }
        return response.json()
      } catch (error) {
        if (error instanceof PallasTradeError) {
          throw error
        }
        const isLastAttempt = attempt >= maxAttempts - 1
        if (
          !isLastAttempt &&
          config.retryConfig &&
          shouldRetryOnNetworkError(method, config.retryConfig, hasIdempotencyKey)
        ) {
          const delay = calculateDelay(attempt, config.retryConfig)
          await sleep(delay)
          continue
        }
        throw error
      }
    }
    // This should never be reached, but TypeScript needs it
    throw new Error('Unexpected end of retry loop')
  }
}
//# sourceMappingURL=request.js.map
