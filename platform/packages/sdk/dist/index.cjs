'use strict';

// ../sdk-core/dist/index.js
function getParams(params) {
  if (!params) return void 0;
  const result = {};
  if (params.expand?.length) result.expand = params.expand.join(",");
  if (params.fields?.length) result.fields = params.fields.join(",");
  return Object.keys(result).length > 0 ? result : void 0;
}
function resolveRetryConfig(retry) {
  if (retry === false) return false;
  return {
    maxRetries: retry?.maxRetries ?? 2,
    retryOnStatus: retry?.retryOnStatus ?? [429, 500, 502, 503, 504],
    baseDelay: retry?.baseDelay ?? 300,
    maxDelay: retry?.maxDelay ?? 1e4,
    retryOnNetworkError: retry?.retryOnNetworkError ?? true
  };
}
var PASSTHROUGH_KEYS = /* @__PURE__ */ new Set(["page", "limit", "expand", "sort", "fields"]);
function transformListParams(params) {
  const result = {};
  for (const [key, value] of Object.entries(params)) {
    if (value === void 0) continue;
    if (PASSTHROUGH_KEYS.has(key)) {
      result[key] = Array.isArray(value) ? value.join(",") : value;
      continue;
    }
    if (key.startsWith("q[")) {
      result[key] = value;
      continue;
    }
    if (Array.isArray(value)) {
      const base = key.endsWith("[]") ? key.slice(0, -2) : key;
      result[`q[${base}][]`] = value;
    } else {
      result[`q[${key}]`] = value;
    }
  }
  return result;
}
var PallasTradeError = class extends Error {
  code;
  status;
  details;
  constructor(response, status) {
    super(response.error.message);
    this.name = "PallasTradeError";
    this.code = response.error.code;
    this.status = status;
    this.details = response.error.details;
  }
};
function calculateDelay(attempt, config) {
  const exponentialDelay = config.baseDelay * 2 ** attempt;
  const jitter = Math.random() * config.baseDelay;
  return Math.min(exponentialDelay + jitter, config.maxDelay);
}
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
function generateIdempotencyKey() {
  return `pallastrade-sdk-retry-${crypto.randomUUID()}`;
}
function shouldRetryOnStatus(method, status, config, hasIdempotencyKey) {
  const isIdempotent = method === "GET" || method === "HEAD" || hasIdempotencyKey;
  if (isIdempotent) {
    return config.retryOnStatus.includes(status);
  }
  return status === 429;
}
function shouldRetryOnNetworkError(method, config, hasIdempotencyKey) {
  if (!config.retryOnNetworkError) return false;
  return method === "GET" || method === "HEAD" || hasIdempotencyKey;
}
function createRequestFn(config, basePath, auth, defaults) {
  return async function request(method, path, options = {}) {
    const { token, guestToken, idempotencyKey, headers = {}, body, params } = options;
    const locale = options.locale ?? defaults?.locale;
    const currency = options.currency ?? defaults?.currency;
    const country = options.country ?? defaults?.country;
    const channel = options.channel ?? defaults?.channel;
    const browserOrigin = typeof window !== "undefined" ? window.location.origin : void 0;
    const urlBase = config.baseUrl || browserOrigin;
    if (!urlBase) {
      throw new TypeError(
        "sdk-core: baseUrl is required in non-browser environments (no window.location to resolve relative URLs against)"
      );
    }
    const url = new URL(`${config.baseUrl}${basePath}${path}`, urlBase);
    if (params) {
      Object.entries(params).forEach(([key, value]) => {
        if (value !== void 0) {
          if (Array.isArray(value)) {
            for (const v of value) {
              url.searchParams.append(key, String(v));
            }
          } else {
            url.searchParams.set(key, String(value));
          }
        }
      });
    }
    const requestHeaders = {
      "Content-Type": "application/json",
      ...headers
    };
    if (auth.headerValue) {
      requestHeaders[auth.headerName] = auth.headerValue;
    }
    if (token) {
      requestHeaders.Authorization = `Bearer ${token}`;
    }
    if (guestToken) {
      requestHeaders["x-pallastrade-token"] = guestToken;
    }
    if (locale) {
      requestHeaders["x-pallastrade-locale"] = locale;
    }
    if (currency) {
      requestHeaders["x-pallastrade-currency"] = currency;
    }
    if (country) {
      requestHeaders["x-pallastrade-country"] = country;
    }
    if (channel) {
      requestHeaders["x-pallastrade-channel"] = channel;
    }
    const isMutating = method !== "GET" && method !== "HEAD";
    const effectiveIdempotencyKey = idempotencyKey ?? (isMutating && config.retryConfig ? generateIdempotencyKey() : void 0);
    if (effectiveIdempotencyKey) {
      requestHeaders["Idempotency-Key"] = effectiveIdempotencyKey;
    }
    const hasIdempotencyKey = !!effectiveIdempotencyKey;
    const maxAttempts = config.retryConfig ? config.retryConfig.maxRetries + 1 : 1;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        const response = await config.fetchFn(url.toString(), {
          method,
          headers: requestHeaders,
          body: body ? JSON.stringify(body) : void 0,
          credentials: config.credentials
        });
        if (!response.ok) {
          const isLastAttempt = attempt >= maxAttempts - 1;
          if (!isLastAttempt && config.retryConfig && shouldRetryOnStatus(method, response.status, config.retryConfig, hasIdempotencyKey)) {
            const retryAfter = response.headers.get("Retry-After");
            const delay = retryAfter ? Math.min(parseInt(retryAfter, 10) * 1e3, config.retryConfig.maxDelay) : calculateDelay(attempt, config.retryConfig);
            await sleep(delay);
            continue;
          }
          const errorBody = await response.json();
          throw new PallasTradeError(errorBody, response.status);
        }
        if (response.status === 204) {
          return void 0;
        }
        if (response.status === 202) {
          const contentType = response.headers.get("content-type");
          if (contentType?.includes("application/json")) {
            return response.json();
          }
          return void 0;
        }
        return response.json();
      } catch (error) {
        if (error instanceof PallasTradeError) {
          throw error;
        }
        const isLastAttempt = attempt >= maxAttempts - 1;
        if (!isLastAttempt && config.retryConfig && shouldRetryOnNetworkError(method, config.retryConfig, hasIdempotencyKey)) {
          const delay = calculateDelay(attempt, config.retryConfig);
          await sleep(delay);
          continue;
        }
        throw error;
      }
    }
    throw new Error("Unexpected end of retry loop");
  };
}

// src/store-client.ts
var StoreClient = class {
  /**
   * Low-level request function for calling custom API endpoints.
   *
   * Uses the same auth headers, retry logic, and base URL as all built-in resources.
   * Paths are relative to `/api/v3/store`.
   *
   * @example
   * ```ts
   * const brands = await client.request<PaginatedResponse<Brand>>('GET', '/brands')
   * ```
   */
  request;
  constructor(request) {
    this.request = request;
  }
  // ============================================
  // Authentication
  // ============================================
  auth = {
    /**
     * Login with email and password
     */
    login: (credentials) => this.request("POST", "/auth/login", { body: credentials }),
    /**
     * Refresh access token using a refresh token.
     * Returns new access JWT + rotated refresh token.
     * No Authorization header needed — uses refresh_token in body.
     */
    refresh: (params, options) => this.request("POST", "/auth/refresh", { ...options, body: params }),
    /**
     * Logout — revokes the refresh token.
     */
    logout: (params, options) => this.request("POST", "/auth/logout", { ...options, body: params })
  };
  // ============================================
  // Products
  // ============================================
  products = {
    /**
     * List products
     */
    list: (params, options) => this.request("GET", "/products", {
      ...options,
      params: transformListParams({ ...params })
    }),
    /**
     * Get a product by ID or slug
     */
    get: (idOrSlug, params, options) => this.request("GET", `/products/${idOrSlug}`, {
      ...options,
      params: getParams(params)
    }),
    /**
     * Get available filters for products
     * Returns filter options (price range, availability, option types, categories) with counts
     */
    filters: (params, options) => this.request("GET", "/products/filters", {
      ...options,
      params
    })
  };
  // ============================================
  // Categories
  // ============================================
  categories = {
    /**
     * List categories
     */
    list: (params, options) => this.request("GET", "/categories", {
      ...options,
      params: transformListParams({ ...params })
    }),
    /**
     * Get a category by ID or permalink
     */
    get: (idOrPermalink, params, options) => this.request("GET", `/categories/${idOrPermalink}`, {
      ...options,
      params: getParams(params)
    })
  };
  // ============================================
  // Countries, Currencies & Locales
  // ============================================
  countries = {
    /**
     * List countries available in the store
     * Each country includes currency and default_locale derived from its market
     */
    list: (options) => this.request("GET", "/countries", options),
    /**
     * Get a country by ISO code
     * Use `?expand=states` to expand states for address forms
     * @param iso - ISO 3166-1 alpha-2 code (e.g., "US", "DE")
     */
    get: (iso, params, options) => this.request("GET", `/countries/${iso}`, {
      ...options,
      params: getParams(params)
    })
  };
  currencies = {
    /**
     * List currencies supported by the store (derived from markets)
     */
    list: (options) => this.request("GET", "/currencies", options)
  };
  locales = {
    /**
     * List locales supported by the store (derived from markets)
     */
    list: (options) => this.request("GET", "/locales", options)
  };
  // ============================================
  // Policies
  // ============================================
  policies = {
    /**
     * List store policies (return policy, privacy policy, terms of service, etc.)
     */
    list: (options) => this.request("GET", "/policies", options),
    /**
     * Get a policy by slug or prefixed ID
     * @param id - Policy slug (e.g., 'return-policy') or prefixed ID (e.g., 'pol_abc123')
     */
    get: (id, options) => this.request("GET", `/policies/${id}`, options)
  };
  // ============================================
  // Markets
  // ============================================
  markets = {
    /**
     * List all markets for the current store
     */
    list: (options) => this.request("GET", "/markets", options),
    /**
     * Get a market by prefixed ID
     * @param id - Market prefixed ID (e.g., "mkt_k5nR8xLq")
     */
    get: (id, options) => this.request("GET", `/markets/${id}`, options),
    /**
     * Resolve which market applies for a given country
     * @param country - ISO 3166-1 alpha-2 code (e.g., "DE", "US")
     */
    resolve: (country, options) => this.request("GET", "/markets/resolve", {
      ...options,
      params: { country }
    }),
    /**
     * Nested resource: Countries in a market
     */
    countries: {
      /**
       * List countries belonging to a market
       * @param marketId - Market prefixed ID
       */
      list: (marketId, options) => this.request("GET", `/markets/${marketId}/countries`, options),
      /**
       * Get a country by ISO code within a market
       * @param marketId - Market prefixed ID
       * @param iso - Country ISO code (e.g., "DE")
       */
      get: (marketId, iso, params, options) => this.request("GET", `/markets/${marketId}/countries/${iso}`, {
        ...options,
        params: getParams(params)
      })
    }
  };
  // ============================================
  // Carts
  // ============================================
  carts = {
    /**
     * List all active (incomplete) carts for the authenticated user
     */
    list: (options) => this.request("GET", "/carts", options),
    /**
     * Get a cart by prefixed ID
     * @param cartId - Cart prefixed ID (e.g., "cart_abc123")
     */
    get: (cartId, options) => this.request("GET", `/carts/${cartId}`, options),
    /**
     * Create a new cart
     * @param params - Optional cart parameters (e.g., metadata, items)
     */
    create: (params, options) => this.request("POST", "/carts", {
      ...options,
      body: params
    }),
    /**
     * Update a cart (email, addresses, special instructions)
     * @param cartId - Cart prefixed ID
     * @param params - Cart update parameters
     */
    update: (cartId, params, options) => this.request("PATCH", `/carts/${cartId}`, {
      ...options,
      body: params
    }),
    /**
     * Delete/abandon a cart
     * @param cartId - Cart prefixed ID
     */
    delete: (cartId, options) => this.request("DELETE", `/carts/${cartId}`, options),
    /**
     * Associate a guest cart with the currently authenticated user
     * @param cartId - Cart prefixed ID
     * @param options - Must include `token` (JWT) for authentication
     */
    associate: (cartId, options) => this.request("PATCH", `/carts/${cartId}/associate`, options),
    /**
     * Complete the cart and finalize the purchase.
     * Returns an Order (not Cart).
     * @param cartId - Cart prefixed ID
     */
    complete: (cartId, options) => this.request("POST", `/carts/${cartId}/complete`, options),
    /**
     * Nested resource: Line items
     */
    items: {
      /**
       * Add an item to the cart.
       * Returns the updated cart with recalculated totals.
       * @param cartId - Cart prefixed ID
       */
      create: (cartId, params, options) => this.request("POST", `/carts/${cartId}/items`, {
        ...options,
        body: params
      }),
      /**
       * Update a line item quantity.
       * Returns the updated cart with recalculated totals.
       * @param cartId - Cart prefixed ID
       */
      update: (cartId, lineItemId, params, options) => this.request("PATCH", `/carts/${cartId}/items/${lineItemId}`, {
        ...options,
        body: params
      }),
      /**
       * Remove a line item from the cart.
       * Returns the updated cart with recalculated totals.
       * @param cartId - Cart prefixed ID
       */
      delete: (cartId, lineItemId, options) => this.request("DELETE", `/carts/${cartId}/items/${lineItemId}`, options)
    },
    /**
     * Nested resource: Discount codes
     */
    discountCodes: {
      /**
       * Apply a discount code to the cart
       * @param cartId - Cart prefixed ID
       * @param code - Promotion discount code to apply (e.g., 'SAVE10')
       */
      apply: (cartId, code, options) => this.request("POST", `/carts/${cartId}/discount_codes`, {
        ...options,
        body: { code }
      }),
      /**
       * Remove a discount code from the cart
       * @param cartId - Cart prefixed ID
       * @param code - The discount code string to remove (e.g., 'SAVE10')
       */
      remove: (cartId, code, options) => this.request("DELETE", `/carts/${cartId}/discount_codes/${code}`, options)
    },
    /**
     * Nested resource: Gift cards
     */
    giftCards: {
      /**
       * Apply a gift card to the cart.
       * Gift cards are treated as a payment method — the cart total remains unchanged
       * while `amount_due` is reduced.
       * @param cartId - Cart prefixed ID
       * @param code - Gift card code to apply
       */
      apply: (cartId, code, options) => this.request("POST", `/carts/${cartId}/gift_cards`, {
        ...options,
        body: { code }
      }),
      /**
       * Remove the applied gift card from the cart
       * @param cartId - Cart prefixed ID
       * @param giftCardId - Gift card prefixed ID (e.g., 'gc_abc123')
       */
      remove: (cartId, giftCardId, options) => this.request("DELETE", `/carts/${cartId}/gift_cards/${giftCardId}`, options)
    },
    /**
     * Nested resource: Fulfillments
     */
    fulfillments: {
      /**
       * Select a delivery rate for a specific fulfillment.
       * Returns the updated cart with recalculated totals.
       * @param cartId - Cart prefixed ID
       */
      update: (cartId, fulfillmentId, params, options) => this.request("PATCH", `/carts/${cartId}/fulfillments/${fulfillmentId}`, {
        ...options,
        body: params
      })
    },
    /**
     * Nested resource: Payments
     */
    payments: {
      /**
       * Create a payment for a non-session payment method (e.g. Check, Cash on Delivery, Bank Transfer).
       * For session-based payment methods (e.g. Stripe, PayPal), use carts.paymentSessions.create() instead.
       * @param cartId - Cart prefixed ID
       */
      create: (cartId, params, options) => this.request("POST", `/carts/${cartId}/payments`, { ...options, body: params })
    },
    /**
     * Nested resource: Payment sessions
     */
    paymentSessions: {
      /**
       * Create a payment session for the cart.
       * Delegates to the payment gateway to initialize a provider-specific session.
       * @param cartId - Cart prefixed ID
       */
      create: (cartId, params, options) => this.request("POST", `/carts/${cartId}/payment_sessions`, {
        ...options,
        body: params
      }),
      /**
       * Get a payment session by ID
       * @param cartId - Cart prefixed ID
       */
      get: (cartId, sessionId, options) => this.request(
        "GET",
        `/carts/${cartId}/payment_sessions/${sessionId}`,
        options
      ),
      /**
       * Update a payment session.
       * Delegates to the payment gateway to sync changes with the provider.
       * @param cartId - Cart prefixed ID
       */
      update: (cartId, sessionId, params, options) => this.request("PATCH", `/carts/${cartId}/payment_sessions/${sessionId}`, {
        ...options,
        body: params
      }),
      /**
       * Complete a payment session.
       * Confirms the payment with the provider, triggering capture/authorization.
       * @param cartId - Cart prefixed ID
       */
      complete: (cartId, sessionId, params, options) => this.request(
        "PATCH",
        `/carts/${cartId}/payment_sessions/${sessionId}/complete`,
        { ...options, body: params }
      )
    },
    /**
     * Store credits
     */
    storeCredits: {
      /**
       * Apply store credit to the cart
       * @param cartId - Cart prefixed ID
       */
      apply: (cartId, amount, options) => this.request("POST", `/carts/${cartId}/store_credits`, {
        ...options,
        body: amount ? { amount } : void 0
      }),
      /**
       * Remove store credit from the cart
       * @param cartId - Cart prefixed ID
       */
      remove: (cartId, options) => this.request("DELETE", `/carts/${cartId}/store_credits`, options)
    }
  };
  // ============================================
  // Orders (post-purchase, read-only)
  // ============================================
  orders = {
    /**
     * Get a completed order by prefixed ID.
     * Accessible via JWT (authenticated users) or guestToken (guests).
     */
    get: (id, params, options) => this.request("GET", `/orders/${id}`, {
      ...options,
      params: getParams(params)
    })
  };
  // ============================================
  // Customer
  // ============================================
  customers = {
    /**
     * Register a new customer account
     */
    create: (params) => this.request("POST", "/customers", { body: params })
  };
  // ============================================
  // Newsletter Subscribers
  // ============================================
  newsletterSubscribers = {
    /**
     * Subscribe an email address to the newsletter for the current store.
     * Guests get an unverified record; pass a JWT via `options.token` to link
     * to a customer (auto-verifies when the JWT email matches `params.email`).
     * `redirect_url` is dropped from the webhook payload when it's not in the
     * store's allowed origins.
     */
    create: (params, options) => this.request("POST", "/newsletter_subscribers", {
      ...options,
      body: params
    }),
    /**
     * Confirm a pending subscription using the token from the confirmation email.
     */
    verify: (params, options) => this.request("POST", "/newsletter_subscribers/verify", {
      ...options,
      body: params
    })
  };
  // ============================================
  // Back-in-stock subscriptions
  // ============================================
  backInStockSubscriptions = {
    /**
     * Subscribe an email to be notified when an out-of-stock product is back in stock.
     */
    create: (productId, params, options) => this.request("POST", `/products/${productId}/back_in_stock_subscriptions`, {
      ...options,
      body: params
    })
  };
  customer = {
    /**
     * Get current customer profile
     */
    get: (options) => this.request("GET", "/customers/me", options),
    /**
     * Update current customer profile
     */
    update: (params, options) => this.request("PATCH", "/customers/me", {
      ...options,
      body: params
    }),
    /**
     * Nested resource: Addresses
     */
    addresses: {
      /**
       * List customer addresses
       */
      list: (params, options) => this.request("GET", "/customers/me/addresses", {
        ...options,
        params: transformListParams({ ...params })
      }),
      /**
       * Get an address by ID
       */
      get: (id, options) => this.request("GET", `/customers/me/addresses/${id}`, options),
      /**
       * Create an address
       */
      create: (params, options) => this.request("POST", "/customers/me/addresses", {
        ...options,
        body: params
      }),
      /**
       * Update an address
       */
      update: (id, params, options) => this.request("PATCH", `/customers/me/addresses/${id}`, {
        ...options,
        body: params
      }),
      /**
       * Delete an address
       */
      delete: (id, options) => this.request("DELETE", `/customers/me/addresses/${id}`, options)
    },
    /**
     * Nested resource: Credit Cards
     */
    creditCards: {
      /**
       * List customer credit cards
       */
      list: (params, options) => this.request("GET", "/customers/me/credit_cards", {
        ...options,
        params: transformListParams({ ...params })
      }),
      /**
       * Get a credit card by ID
       */
      get: (id, options) => this.request("GET", `/customers/me/credit_cards/${id}`, options),
      /**
       * Delete a credit card
       */
      delete: (id, options) => this.request("DELETE", `/customers/me/credit_cards/${id}`, options)
    },
    /**
     * Nested resource: Gift Cards
     */
    giftCards: {
      /**
       * List customer gift cards
       * Returns gift cards associated with the current user, ordered by newest first
       */
      list: (params, options) => this.request("GET", "/customers/me/gift_cards", {
        ...options,
        params: transformListParams({ ...params })
      }),
      /**
       * Get a gift card by ID
       */
      get: (id, options) => this.request("GET", `/customers/me/gift_cards/${id}`, options)
    },
    /**
     * Nested resource: Store Credits
     */
    storeCredits: {
      /**
       * List store credits for the authenticated customer.
       * Filtered by current store and currency.
       * Supports Ransack filtering (e.g. `q[amount_remaining_gt]: 0`).
       */
      list: (params, options) => this.request("GET", "/customers/me/store_credits", {
        ...options,
        params: transformListParams({ ...params })
      }),
      /**
       * Get a store credit by ID
       */
      get: (id, options) => this.request("GET", `/customers/me/store_credits/${id}`, options)
    },
    /**
     * Nested resource: Orders (customer order history)
     */
    orders: {
      /**
       * List completed orders for the authenticated customer
       */
      list: (params, options) => this.request("GET", "/customers/me/orders", {
        ...options,
        params: transformListParams({ ...params })
      }),
      /**
       * Get a completed order by prefixed ID
       */
      get: (id, params, options) => this.request("GET", `/customers/me/orders/${id}`, {
        ...options,
        params: getParams(params)
      })
    },
    /**
     * Nested resource: Payment Setup Sessions (save payment methods for future use)
     */
    paymentSetupSessions: {
      /**
       * Create a payment setup session
       * Delegates to the payment gateway to initialize a setup flow for saving a payment method
       */
      create: (params, options) => this.request("POST", "/customers/me/payment_setup_sessions", {
        ...options,
        body: params
      }),
      /**
       * Get a payment setup session by ID
       */
      get: (id, options) => this.request(
        "GET",
        `/customers/me/payment_setup_sessions/${id}`,
        options
      ),
      /**
       * Complete a payment setup session
       * Confirms the setup with the provider, resulting in a saved payment method
       */
      complete: (id, params, options) => this.request(
        "PATCH",
        `/customers/me/payment_setup_sessions/${id}/complete`,
        { ...options, body: params }
      )
    }
  };
  // ============================================
  // Password Resets
  // ============================================
  passwordResets = {
    /**
     * Request a password reset email.
     * Always succeeds (202) to prevent email enumeration.
     */
    create: (params) => this.request("POST", "/password_resets", {
      body: params
    }),
    /**
     * Reset password using the token from the email.
     * Returns a JWT token on success (auto-login).
     * @param token - Password reset token from the email
     */
    update: (token, params) => this.request("PATCH", `/password_resets/${token}`, { body: params })
  };
  // ============================================
  // Wishlists
  // ============================================
  wishlists = {
    /**
     * List wishlists
     */
    list: (params, options) => this.request("GET", "/wishlists", {
      ...options,
      params: transformListParams({ ...params })
    }),
    /**
     * Get a wishlist by ID
     */
    get: (id, params, options) => this.request("GET", `/wishlists/${id}`, {
      ...options,
      params: getParams(params)
    }),
    /**
     * Create a wishlist
     */
    create: (params, options) => this.request("POST", "/wishlists", {
      ...options,
      body: params
    }),
    /**
     * Update a wishlist
     */
    update: (id, params, options) => this.request("PATCH", `/wishlists/${id}`, {
      ...options,
      body: params
    }),
    /**
     * Delete a wishlist
     */
    delete: (id, options) => this.request("DELETE", `/wishlists/${id}`, options),
    /**
     * Nested resource: Wishlist items
     */
    items: {
      /**
       * Add an item to a wishlist
       */
      create: (wishlistId, params, options) => this.request("POST", `/wishlists/${wishlistId}/items`, {
        ...options,
        body: params
      }),
      /**
       * Update a wishlist item
       */
      update: (wishlistId, itemId, params, options) => this.request("PATCH", `/wishlists/${wishlistId}/items/${itemId}`, {
        ...options,
        body: params
      }),
      /**
       * Remove an item from a wishlist
       */
      delete: (wishlistId, itemId, options) => this.request("DELETE", `/wishlists/${wishlistId}/items/${itemId}`, options)
    }
  };
};

// src/client.ts
function createClient(config) {
  const baseUrl = config.baseUrl.replace(/\/$/, "");
  const fetchFn = config.fetch || fetch.bind(globalThis);
  const defaults = {
    locale: config.locale,
    currency: config.currency,
    country: config.country,
    channel: config.channel
  };
  const retryConfig = resolveRetryConfig(config.retry);
  const requestConfig = { baseUrl, fetchFn, retryConfig };
  const requestFn = createRequestFn(
    requestConfig,
    "/api/v3/store",
    { headerName: "x-pallastrade-api-key", headerValue: config.publishableKey },
    defaults
  );
  const storeClient = new StoreClient(requestFn);
  const client = Object.create(storeClient);
  client.setLocale = (locale) => {
    defaults.locale = locale;
  };
  client.setCurrency = (currency) => {
    defaults.currency = currency;
  };
  client.setCountry = (country) => {
    defaults.country = country;
  };
  client.setChannel = (channel) => {
    defaults.channel = channel;
  };
  return client;
}

exports.PallasTradeError = PallasTradeError;
exports.StoreClient = StoreClient;
exports.createClient = createClient;
//# sourceMappingURL=index.cjs.map
//# sourceMappingURL=index.cjs.map