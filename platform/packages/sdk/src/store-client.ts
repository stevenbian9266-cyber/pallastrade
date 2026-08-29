import type {
  AddressParams,
  ListParams,
  ListResponse,
  PaginatedResponse,
  RequestFn,
  RequestOptions,
} from '@pallastrade/sdk-core'
import { getParams, transformListParams } from '@pallastrade/sdk-core'
import type {
  AddLineItemParams,
  Address,
  AuthTokens,
  Cart,
  Category,
  CategoryListParams,
  CompletePaymentSessionParams,
  CompletePaymentSetupSessionParams,
  Country,
  CreateCartParams,
  CreatePaymentCombinationParams,
  CreatePaymentParams,
  CreatePaymentSessionParams,
  CreatePaymentSetupSessionParams,
  CreditCard,
  Currency,
  Customer,
  DeliveryMethod,
  GiftCard,
  Locale,
  LoginCredentials,
  Market,
  NewsletterSubscriber,
  Order,
  OrderListParams,
  Payment,
  PaymentCombination,
  PaymentSession,
  PaymentSetupSession,
  Policy,
  Post,
  Product,
  ProductFiltersParams,
  ProductFiltersResponse,
  ProductListParams,
  RegisterParams,
  RequestPasswordResetParams,
  ResetPasswordParams,
  StoreCredit,
  UpdateCartParams,
  UpdateLineItemParams,
  UpdatePaymentSessionParams,
  Wishlist,
  WishlistItem,
} from './types'

export class StoreClient {
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
  readonly request: RequestFn

  constructor(request: RequestFn) {
    this.request = request
  }

  // ============================================
  // Authentication
  // ============================================

  readonly auth = {
    /**
     * Login with email and password
     */
    login: (credentials: LoginCredentials): Promise<AuthTokens> =>
      this.request<AuthTokens>('POST', '/auth/login', { body: credentials }),

    /**
     * Refresh access token using a refresh token.
     * Returns new access JWT + rotated refresh token.
     * No Authorization header needed — uses refresh_token in body.
     */
    refresh: (params: { refresh_token: string }, options?: RequestOptions): Promise<AuthTokens> =>
      this.request<AuthTokens>('POST', '/auth/refresh', { ...options, body: params }),

    /**
     * Logout — revokes the refresh token.
     */
    logout: (params: { refresh_token: string }, options?: RequestOptions): Promise<void> =>
      this.request<void>('POST', '/auth/logout', { ...options, body: params }),
  }

  // ============================================
  // Products
  // ============================================

  readonly products = {
    /**
     * List products
     */
    list: (
      params?: ProductListParams,
      options?: RequestOptions,
    ): Promise<PaginatedResponse<Product>> =>
      this.request<PaginatedResponse<Product>>('GET', '/products', {
        ...options,
        params: transformListParams({ ...params }),
      }),

    /**
     * Get a product by ID or slug
     */
    get: (
      idOrSlug: string,
      params?: { expand?: string[]; fields?: string[] },
      options?: RequestOptions,
    ): Promise<Product> =>
      this.request<Product>('GET', `/products/${idOrSlug}`, {
        ...options,
        params: getParams(params),
      }),

    /**
     * Get available filters for products
     * Returns filter options (price range, availability, option types, categories) with counts
     */
    filters: (
      params?: ProductFiltersParams,
      options?: RequestOptions,
    ): Promise<ProductFiltersResponse> =>
      this.request<ProductFiltersResponse>('GET', '/products/filters', {
        ...options,
        params: params as Record<string, string | number | undefined>,
      }),

    /**
     * Product reviews (P0-4).
     * `list` returns approved reviews (guest-accessible); `create` submits a
     * review as the signed-in customer (pass a JWT via `options.token`).
     */
    reviews: {
      list: (
        productId: string,
        params?: { fields?: string[] },
        options?: RequestOptions,
      ): Promise<
        Array<{
          id: string
          product_id: string | null
          user_name: string | null
          rating: number
          title: string | null
          body: string | null
          verified_purchase: boolean
          created_at: string | null
        }>
      > =>
        this.request('GET', `/products/${productId}/reviews`, {
          ...options,
          params: getParams(params),
        }),

      create: (
        productId: string,
        params: { rating: number; title?: string; body?: string },
        options?: RequestOptions,
      ): Promise<{
        id: string
        product_id: string | null
        user_name: string | null
        rating: number
        title: string | null
        body: string | null
        verified_purchase: boolean
        created_at: string | null
      }> =>
        this.request('POST', `/products/${productId}/reviews`, {
          ...options,
          body: params,
        }),
    },
  }

  // ============================================
  // Categories
  // ============================================

  readonly categories = {
    /**
     * List categories
     */
    list: (
      params?: CategoryListParams,
      options?: RequestOptions,
    ): Promise<PaginatedResponse<Category>> =>
      this.request<PaginatedResponse<Category>>('GET', '/categories', {
        ...options,
        params: transformListParams({ ...params }),
      }),

    /**
     * Get a category by ID or permalink
     */
    get: (
      idOrPermalink: string,
      params?: { expand?: string[]; fields?: string[] },
      options?: RequestOptions,
    ): Promise<Category> =>
      this.request<Category>('GET', `/categories/${idOrPermalink}`, {
        ...options,
        params: getParams(params),
      }),
  }

  // ============================================
  // Countries, Currencies & Locales
  // ============================================

  readonly countries = {
    /**
     * List countries available in the store
     * Each country includes currency and default_locale derived from its market
     */
    list: (options?: RequestOptions): Promise<ListResponse<Country>> =>
      this.request<ListResponse<Country>>('GET', '/countries', options),

    /**
     * Get a country by ISO code
     * Use `?expand=states` to expand states for address forms
     * @param iso - ISO 3166-1 alpha-2 code (e.g., "US", "DE")
     */
    get: (
      iso: string,
      params?: { expand?: string[]; fields?: string[] },
      options?: RequestOptions,
    ): Promise<Country> =>
      this.request<Country>('GET', `/countries/${iso}`, {
        ...options,
        params: getParams(params),
      }),
  }

  readonly currencies = {
    /**
     * List currencies supported by the store (derived from markets)
     */
    list: (options?: RequestOptions): Promise<ListResponse<Currency>> =>
      this.request<ListResponse<Currency>>('GET', '/currencies', options),
  }

  readonly locales = {
    /**
     * List locales supported by the store (derived from markets)
     */
    list: (options?: RequestOptions): Promise<ListResponse<Locale>> =>
      this.request<ListResponse<Locale>>('GET', '/locales', options),
  }

  // ============================================
  // Policies
  // ============================================

  readonly policies = {
    /**
     * List store policies (return policy, privacy policy, terms of service, etc.)
     */
    list: (options?: RequestOptions): Promise<ListResponse<Policy>> =>
      this.request<ListResponse<Policy>>('GET', '/policies', options),

    /**
     * Get a policy by slug or prefixed ID
     * @param id - Policy slug (e.g., 'return-policy') or prefixed ID (e.g., 'pol_abc123')
     */
    get: (id: string, options?: RequestOptions): Promise<Policy> =>
      this.request<Policy>('GET', `/policies/${id}`, options),
  }

  // ============================================
  // Posts (blog)
  // ============================================

  readonly posts = {
    /**
     * List published blog posts (newest first, paginated)
     */
    list: (params?: ListParams, options?: RequestOptions): Promise<PaginatedResponse<Post>> =>
      this.request<PaginatedResponse<Post>>('GET', '/posts', {
        ...options,
        params: transformListParams({ ...params }),
      }),

    /**
     * Get a published blog post by slug or prefixed ID
     * @param id - Post slug (e.g., 'welcome-to-our-store') or prefixed ID (e.g., 'post_abc123')
     */
    get: (id: string, options?: RequestOptions): Promise<Post> =>
      this.request<Post>('GET', `/posts/${id}`, options),
  }

  // ============================================
  // Markets
  // ============================================

  readonly markets = {
    /**
     * List all markets for the current store
     */
    list: (options?: RequestOptions): Promise<ListResponse<Market>> =>
      this.request<ListResponse<Market>>('GET', '/markets', options),

    /**
     * Get a market by prefixed ID
     * @param id - Market prefixed ID (e.g., "mkt_k5nR8xLq")
     */
    get: (id: string, options?: RequestOptions): Promise<Market> =>
      this.request<Market>('GET', `/markets/${id}`, options),

    /**
     * Resolve which market applies for a given country
     * @param country - ISO 3166-1 alpha-2 code (e.g., "DE", "US")
     */
    resolve: (country: string, options?: RequestOptions): Promise<Market> =>
      this.request<Market>('GET', '/markets/resolve', {
        ...options,
        params: { country },
      }),

    /**
     * Nested resource: Countries in a market
     */
    countries: {
      /**
       * List countries belonging to a market
       * @param marketId - Market prefixed ID
       */
      list: (marketId: string, options?: RequestOptions): Promise<ListResponse<Country>> =>
        this.request<ListResponse<Country>>('GET', `/markets/${marketId}/countries`, options),

      /**
       * Get a country by ISO code within a market
       * @param marketId - Market prefixed ID
       * @param iso - Country ISO code (e.g., "DE")
       */
      get: (
        marketId: string,
        iso: string,
        params?: { expand?: string[]; fields?: string[] },
        options?: RequestOptions,
      ): Promise<Country> =>
        this.request<Country>('GET', `/markets/${marketId}/countries/${iso}`, {
          ...options,
          params: getParams(params),
        }),
    },
  }

  // ============================================
  // Carts
  // ============================================

  readonly carts = {
    /**
     * List all active (incomplete) carts for the authenticated user
     */
    list: (options?: RequestOptions): Promise<PaginatedResponse<Cart>> =>
      this.request<PaginatedResponse<Cart>>('GET', '/carts', options),

    /**
     * Get a cart by prefixed ID
     * @param cartId - Cart prefixed ID (e.g., "cart_abc123")
     */
    get: (cartId: string, options?: RequestOptions): Promise<Cart> =>
      this.request<Cart>('GET', `/carts/${cartId}`, options),

    /**
     * Create a new cart
     * @param params - Optional cart parameters (e.g., metadata, items)
     */
    create: (params?: CreateCartParams, options?: RequestOptions): Promise<Cart> =>
      this.request<Cart>('POST', '/carts', {
        ...options,
        body: params,
      }),

    /**
     * Update a cart (email, addresses, special instructions)
     * @param cartId - Cart prefixed ID
     * @param params - Cart update parameters
     */
    update: (cartId: string, params: UpdateCartParams, options?: RequestOptions): Promise<Cart> =>
      this.request<Cart>('PATCH', `/carts/${cartId}`, {
        ...options,
        body: params,
      }),

    /**
     * Delete/abandon a cart
     * @param cartId - Cart prefixed ID
     */
    delete: (cartId: string, options?: RequestOptions): Promise<void> =>
      this.request<void>('DELETE', `/carts/${cartId}`, options),

    /**
     * Associate a guest cart with the currently authenticated user
     * @param cartId - Cart prefixed ID
     * @param options - Must include `token` (JWT) for authentication
     */
    associate: (cartId: string, options: RequestOptions): Promise<Cart> =>
      this.request<Cart>('PATCH', `/carts/${cartId}/associate`, options),

    /**
     * Complete the cart and finalize the purchase.
     * Returns an Order (not Cart).
     * @param cartId - Cart prefixed ID
     */
    complete: (cartId: string, options?: RequestOptions): Promise<Order> =>
      this.request<Order>('POST', `/carts/${cartId}/complete`, options),

    /**
     * P1 (2026-08-30): Submit the cart — creates a pending Order (standard flow)
     * from the selected cart items and converts the cart.
     * Returns an Order (not Cart). Client should then navigate to /checkout/[orderId].
     * @param cartId - Cart prefixed ID
     */
    submit: (cartId: string, options?: RequestOptions): Promise<Order> =>
      this.request<Order>('POST', `/carts/${cartId}/submit`, options),

    /**
     * Nested resource: Line items
     */
    items: {
      /**
       * Add an item to the cart.
       * Returns the updated cart with recalculated totals.
       * @param cartId - Cart prefixed ID
       */
      create: (
        cartId: string,
        params: AddLineItemParams,
        options?: RequestOptions,
      ): Promise<Cart> =>
        this.request<Cart>('POST', `/carts/${cartId}/items`, {
          ...options,
          body: params,
        }),

      /**
       * Update a line item quantity.
       * Returns the updated cart with recalculated totals.
       * @param cartId - Cart prefixed ID
       */
      update: (
        cartId: string,
        lineItemId: string,
        params: UpdateLineItemParams,
        options?: RequestOptions,
      ): Promise<Cart> =>
        this.request<Cart>('PATCH', `/carts/${cartId}/items/${lineItemId}`, {
          ...options,
          body: params,
        }),

      /**
       * Remove a line item from the cart.
       * Returns the updated cart with recalculated totals.
       * @param cartId - Cart prefixed ID
       */
      delete: (cartId: string, lineItemId: string, options?: RequestOptions): Promise<Cart> =>
        this.request<Cart>('DELETE', `/carts/${cartId}/items/${lineItemId}`, options),
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
      apply: (cartId: string, code: string, options?: RequestOptions): Promise<Cart> =>
        this.request<Cart>('POST', `/carts/${cartId}/discount_codes`, {
          ...options,
          body: { code },
        }),

      /**
       * Remove a discount code from the cart
       * @param cartId - Cart prefixed ID
       * @param code - The discount code string to remove (e.g., 'SAVE10')
       */
      remove: (cartId: string, code: string, options?: RequestOptions): Promise<Cart> =>
        this.request<Cart>('DELETE', `/carts/${cartId}/discount_codes/${code}`, options),
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
      apply: (cartId: string, code: string, options?: RequestOptions): Promise<Cart> =>
        this.request<Cart>('POST', `/carts/${cartId}/gift_cards`, {
          ...options,
          body: { code },
        }),

      /**
       * Remove the applied gift card from the cart
       * @param cartId - Cart prefixed ID
       * @param giftCardId - Gift card prefixed ID (e.g., 'gc_abc123')
       */
      remove: (cartId: string, giftCardId: string, options?: RequestOptions): Promise<Cart> =>
        this.request<Cart>('DELETE', `/carts/${cartId}/gift_cards/${giftCardId}`, options),
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
      update: (
        cartId: string,
        fulfillmentId: string,
        params: { selected_delivery_rate_id: string },
        options?: RequestOptions,
      ): Promise<Cart> =>
        this.request<Cart>('PATCH', `/carts/${cartId}/fulfillments/${fulfillmentId}`, {
          ...options,
          body: params,
        }),
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
      create: (
        cartId: string,
        params: CreatePaymentParams,
        options?: RequestOptions,
      ): Promise<Payment> =>
        this.request<Payment>('POST', `/carts/${cartId}/payments`, { ...options, body: params }),
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
      create: (
        cartId: string,
        params: CreatePaymentSessionParams,
        options?: RequestOptions,
      ): Promise<PaymentSession> =>
        this.request<PaymentSession>('POST', `/carts/${cartId}/payment_sessions`, {
          ...options,
          body: params,
        }),

      /**
       * Get a payment session by ID
       * @param cartId - Cart prefixed ID
       */
      get: (cartId: string, sessionId: string, options?: RequestOptions): Promise<PaymentSession> =>
        this.request<PaymentSession>(
          'GET',
          `/carts/${cartId}/payment_sessions/${sessionId}`,
          options,
        ),

      /**
       * Update a payment session.
       * Delegates to the payment gateway to sync changes with the provider.
       * @param cartId - Cart prefixed ID
       */
      update: (
        cartId: string,
        sessionId: string,
        params: UpdatePaymentSessionParams,
        options?: RequestOptions,
      ): Promise<PaymentSession> =>
        this.request<PaymentSession>('PATCH', `/carts/${cartId}/payment_sessions/${sessionId}`, {
          ...options,
          body: params,
        }),

      /**
       * Complete a payment session.
       * Confirms the payment with the provider, triggering capture/authorization.
       * @param cartId - Cart prefixed ID
       */
      complete: (
        cartId: string,
        sessionId: string,
        params?: CompletePaymentSessionParams,
        options?: RequestOptions,
      ): Promise<PaymentSession> =>
        this.request<PaymentSession>(
          'PATCH',
          `/carts/${cartId}/payment_sessions/${sessionId}/complete`,
          { ...options, body: params },
        ),
    },

    /**
     * Store credits
     */
    storeCredits: {
      /**
       * Apply store credit to the cart
       * @param cartId - Cart prefixed ID
       */
      apply: (cartId: string, amount?: number, options?: RequestOptions): Promise<Cart> =>
        this.request<Cart>('POST', `/carts/${cartId}/store_credits`, {
          ...options,
          body: amount ? { amount } : undefined,
        }),

      /**
       * Remove store credit from the cart
       * @param cartId - Cart prefixed ID
       */
      remove: (cartId: string, options?: RequestOptions): Promise<Cart> =>
        this.request<Cart>('DELETE', `/carts/${cartId}/store_credits`, options),
    },
  }

  // ============================================
  // Shipping Methods (P1, 2026-08-30) — 订单确认页可选配送方式
  // ============================================

  readonly shippingMethods = {
    /**
     * List front-end shipping methods (name/description with rate label).
     */
    list: (options?: RequestOptions): Promise<DeliveryMethod[]> =>
      this.request<DeliveryMethod[]>('GET', '/shipping_methods', options),
  }

  // ============================================
  // Orders (post-purchase, read-only)
  // ============================================

  readonly orders = {
    /**
     * Get a completed order by prefixed ID.
     * Accessible via JWT (authenticated users) or guestToken (guests).
     */
    get: (
      id: string,
      params?: { expand?: string[]; fields?: string[] },
      options?: RequestOptions,
    ): Promise<Order> =>
      this.request<Order>('GET', `/orders/${id}`, {
        ...options,
        params: getParams(params),
      }),

    /**
     * P1 (2026-08-30): Nested payment sessions — Checkout 纯支付在订单域创建/完成支付会话。
     * 与 legacy `carts.paymentSessions`（Order 同表购物车）不同，标准流程订单是正式 Order。
     */
    paymentSessions: {
      /**
       * Create a payment session for the order.
       */
      create: (
        orderId: string,
        params: CreatePaymentSessionParams,
        options?: RequestOptions,
      ): Promise<PaymentSession> =>
        this.request<PaymentSession>('POST', `/orders/${orderId}/payment_sessions`, {
          ...options,
          body: params,
        }),

      /**
       * Get a payment session by ID.
       */
      get: (
        orderId: string,
        sessionId: string,
        options?: RequestOptions,
      ): Promise<PaymentSession> =>
        this.request<PaymentSession>('GET', `/orders/${orderId}/payment_sessions/${sessionId}`, options),

      /**
       * Complete a payment session (confirm payment with the provider).
       */
      complete: (
        orderId: string,
        sessionId: string,
        params?: CompletePaymentSessionParams,
        options?: RequestOptions,
      ): Promise<PaymentSession> =>
        this.request<PaymentSession>(
          'PATCH',
          `/orders/${orderId}/payment_sessions/${sessionId}/complete`,
          { ...options, body: params },
        ),
    },
  }

  // ============================================
  // Customer
  // ============================================

  readonly customers = {
    /**
     * Register a new customer account
     */
    create: (params: RegisterParams): Promise<AuthTokens> =>
      this.request<AuthTokens>('POST', '/customers', { body: params }),
  }

  // ============================================
  // Payment Combinations (P5, 2026-08-27)
  // ============================================

  readonly paymentCombinations = {
    /**
     * Create a payment combination: combine multiple unpaid orders into a
     * single checkout payment (amount is server-computed).
     * POST /api/v3/store/payment_combinations
     * @param params - Prefixed order IDs + payment method
     * @returns The created combination (with its payment session for the checkout)
     */
    create: (
      params: CreatePaymentCombinationParams,
      options?: RequestOptions,
    ): Promise<PaymentCombination> =>
      this.request<PaymentCombination>('POST', '/payment_combinations', {
        ...options,
        body: params,
      }),

    /**
     * Get a payment combination by ID (for the combined-payment checkout page).
     * GET /api/v3/store/payment_combinations/:id
     */
    get: (
      id: string,
      options?: RequestOptions,
    ): Promise<PaymentCombination> =>
      this.request<PaymentCombination>('GET', `/payment_combinations/${id}`, options),
  }

  // ============================================
  // Newsletter Subscribers
  // ============================================

  readonly newsletterSubscribers = {
    /**
     * Subscribe an email address to the newsletter for the current store.
     * Guests get an unverified record; pass a JWT via `options.token` to link
     * to a customer (auto-verifies when the JWT email matches `params.email`).
     * `redirect_url` is dropped from the webhook payload when it's not in the
     * store's allowed origins.
     */
    create: (
      params: { email: string; redirect_url?: string },
      options?: RequestOptions,
    ): Promise<NewsletterSubscriber> =>
      this.request<NewsletterSubscriber>('POST', '/newsletter_subscribers', {
        ...options,
        body: params,
      }),

    /**
     * Confirm a pending subscription using the token from the confirmation email.
     */
    verify: (params: { token: string }, options?: RequestOptions): Promise<NewsletterSubscriber> =>
      this.request<NewsletterSubscriber>('POST', '/newsletter_subscribers/verify', {
        ...options,
        body: params,
      }),
  }

  // ============================================
  // Back-in-stock subscriptions
  // ============================================

  readonly backInStockSubscriptions = {
    /**
     * Subscribe an email to be notified when an out-of-stock product is back in stock.
     */
    create: (
      productId: string,
      params: { email: string },
      options?: RequestOptions,
    ): Promise<{
      id: string
      email: string
      status: string
      product_id: string | null
      created_at: string
    }> =>
      this.request('POST', `/products/${productId}/back_in_stock_subscriptions`, {
        ...options,
        body: params,
      }),
  }

  // ============================================
  // Contact messages (complaints / feedback)
  // ============================================

  readonly contactMessages = {
    /**
     * Submit a complaint, feedback or inquiry from the storefront. Guest-accessible.
     * Classified by `kind` and surfaced in the admin Email → Inbox & Feedback page.
     */
    create: (
      params: {
        kind: "complaint" | "feedback" | "inquiry"
        name?: string
        email: string
        subject?: string
        body: string
      },
      options?: RequestOptions,
    ): Promise<{
      id: string
      kind: string
      name: string | null
      email: string
      subject: string | null
      body: string
      status: string
      created_at: string
    }> =>
      this.request('POST', '/contact_messages', {
        ...options,
        body: params,
      }),
  }

  readonly customer = {
    /**
     * Get current customer profile
     */
    get: (options?: RequestOptions): Promise<Customer> =>
      this.request<Customer>('GET', '/customers/me', options),

    /**
     * Update current customer profile
     */
    update: (
      params: {
        first_name?: string
        last_name?: string
        email?: string
        password?: string
        password_confirmation?: string
        /** Required when changing email or password */
        current_password?: string
        accepts_email_marketing?: boolean
        phone?: string
        /** Arbitrary key-value metadata (stored, not returned in responses) */
        metadata?: Record<string, unknown>
      },
      options?: RequestOptions,
    ): Promise<Customer> =>
      this.request<Customer>('PATCH', '/customers/me', {
        ...options,
        body: params,
      }),

    /**
     * Nested resource: Addresses
     */
    addresses: {
      /**
       * List customer addresses
       */
      list: (params?: ListParams, options?: RequestOptions): Promise<PaginatedResponse<Address>> =>
        this.request<PaginatedResponse<Address>>('GET', '/customers/me/addresses', {
          ...options,
          params: transformListParams({ ...params }),
        }),

      /**
       * Get an address by ID
       */
      get: (id: string, options?: RequestOptions): Promise<Address> =>
        this.request<Address>('GET', `/customers/me/addresses/${id}`, options),

      /**
       * Create an address
       */
      create: (params: AddressParams, options?: RequestOptions): Promise<Address> =>
        this.request<Address>('POST', '/customers/me/addresses', {
          ...options,
          body: params,
        }),

      /**
       * Update an address
       */
      update: (
        id: string,
        params: Partial<AddressParams>,
        options?: RequestOptions,
      ): Promise<Address> =>
        this.request<Address>('PATCH', `/customers/me/addresses/${id}`, {
          ...options,
          body: params,
        }),

      /**
       * Delete an address
       */
      delete: (id: string, options?: RequestOptions): Promise<void> =>
        this.request<void>('DELETE', `/customers/me/addresses/${id}`, options),
    },

    /**
     * Nested resource: Credit Cards
     */
    creditCards: {
      /**
       * List customer credit cards
       */
      list: (
        params?: ListParams,
        options?: RequestOptions,
      ): Promise<PaginatedResponse<CreditCard>> =>
        this.request<PaginatedResponse<CreditCard>>('GET', '/customers/me/credit_cards', {
          ...options,
          params: transformListParams({ ...params }),
        }),

      /**
       * Get a credit card by ID
       */
      get: (id: string, options?: RequestOptions): Promise<CreditCard> =>
        this.request<CreditCard>('GET', `/customers/me/credit_cards/${id}`, options),

      /**
       * Delete a credit card
       */
      delete: (id: string, options?: RequestOptions): Promise<void> =>
        this.request<void>('DELETE', `/customers/me/credit_cards/${id}`, options),
    },

    /**
     * Nested resource: Gift Cards
     */
    giftCards: {
      /**
       * List customer gift cards
       * Returns gift cards associated with the current user, ordered by newest first
       */
      list: (params?: ListParams, options?: RequestOptions): Promise<PaginatedResponse<GiftCard>> =>
        this.request<PaginatedResponse<GiftCard>>('GET', '/customers/me/gift_cards', {
          ...options,
          params: transformListParams({ ...params }),
        }),

      /**
       * Get a gift card by ID
       */
      get: (id: string, options?: RequestOptions): Promise<GiftCard> =>
        this.request<GiftCard>('GET', `/customers/me/gift_cards/${id}`, options),
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
      list: (
        params?: ListParams,
        options?: RequestOptions,
      ): Promise<PaginatedResponse<StoreCredit>> =>
        this.request<PaginatedResponse<StoreCredit>>('GET', '/customers/me/store_credits', {
          ...options,
          params: transformListParams({ ...params }),
        }),

      /**
       * Get a store credit by ID
       */
      get: (id: string, options?: RequestOptions): Promise<StoreCredit> =>
        this.request<StoreCredit>('GET', `/customers/me/store_credits/${id}`, options),
    },

    /**
     * Nested resource: Orders (customer order history)
     */
    orders: {
      /**
       * List completed orders for the authenticated customer
       */
      list: (
        params?: OrderListParams,
        options?: RequestOptions,
      ): Promise<PaginatedResponse<Order>> =>
        this.request<PaginatedResponse<Order>>('GET', '/customers/me/orders', {
          ...options,
          params: transformListParams({ ...params }),
        }),

      /**
       * Get a completed order by prefixed ID
       */
      get: (
        id: string,
        params?: { expand?: string[]; fields?: string[] },
        options?: RequestOptions,
      ): Promise<Order> =>
        this.request<Order>('GET', `/customers/me/orders/${id}`, {
          ...options,
          params: getParams(params),
        }),
    },

    /**
     * Nested resource: Payment Setup Sessions (save payment methods for future use)
     */
    paymentSetupSessions: {
      /**
       * Create a payment setup session
       * Delegates to the payment gateway to initialize a setup flow for saving a payment method
       */
      create: (
        params: CreatePaymentSetupSessionParams,
        options?: RequestOptions,
      ): Promise<PaymentSetupSession> =>
        this.request<PaymentSetupSession>('POST', '/customers/me/payment_setup_sessions', {
          ...options,
          body: params,
        }),

      /**
       * Get a payment setup session by ID
       */
      get: (id: string, options?: RequestOptions): Promise<PaymentSetupSession> =>
        this.request<PaymentSetupSession>(
          'GET',
          `/customers/me/payment_setup_sessions/${id}`,
          options,
        ),

      /**
       * Complete a payment setup session
       * Confirms the setup with the provider, resulting in a saved payment method
       */
      complete: (
        id: string,
        params?: CompletePaymentSetupSessionParams,
        options?: RequestOptions,
      ): Promise<PaymentSetupSession> =>
        this.request<PaymentSetupSession>(
          'PATCH',
          `/customers/me/payment_setup_sessions/${id}/complete`,
          { ...options, body: params },
        ),
    },
  }

  // ============================================
  // Password Resets
  // ============================================

  readonly passwordResets = {
    /**
     * Request a password reset email.
     * Always succeeds (202) to prevent email enumeration.
     */
    create: (params: RequestPasswordResetParams): Promise<{ message: string }> =>
      this.request<{ message: string }>('POST', '/password_resets', {
        body: params,
      }),

    /**
     * Reset password using the token from the email.
     * Returns a JWT token on success (auto-login).
     * @param token - Password reset token from the email
     */
    update: (token: string, params: ResetPasswordParams): Promise<AuthTokens> =>
      this.request<AuthTokens>('PATCH', `/password_resets/${token}`, { body: params }),
  }

  // ============================================
  // Wishlists
  // ============================================

  readonly wishlists = {
    /**
     * List wishlists
     */
    list: (params?: ListParams, options?: RequestOptions): Promise<PaginatedResponse<Wishlist>> =>
      this.request<PaginatedResponse<Wishlist>>('GET', '/wishlists', {
        ...options,
        params: transformListParams({ ...params }),
      }),

    /**
     * Get a wishlist by ID
     */
    get: (
      id: string,
      params?: { expand?: string[]; fields?: string[] },
      options?: RequestOptions,
    ): Promise<Wishlist> =>
      this.request<Wishlist>('GET', `/wishlists/${id}`, {
        ...options,
        params: getParams(params),
      }),

    /**
     * Create a wishlist
     */
    create: (
      params: { name: string; is_private?: boolean; is_default?: boolean },
      options?: RequestOptions,
    ): Promise<Wishlist> =>
      this.request<Wishlist>('POST', '/wishlists', {
        ...options,
        body: params,
      }),

    /**
     * Update a wishlist
     */
    update: (
      id: string,
      params: { name?: string; is_private?: boolean; is_default?: boolean },
      options?: RequestOptions,
    ): Promise<Wishlist> =>
      this.request<Wishlist>('PATCH', `/wishlists/${id}`, {
        ...options,
        body: params,
      }),

    /**
     * Delete a wishlist
     */
    delete: (id: string, options?: RequestOptions): Promise<void> =>
      this.request<void>('DELETE', `/wishlists/${id}`, options),

    /**
     * Nested resource: Wishlist items
     */
    items: {
      /**
       * Add an item to a wishlist
       */
      create: (
        wishlistId: string,
        params: { variant_id: string; quantity?: number },
        options?: RequestOptions,
      ): Promise<WishlistItem> =>
        this.request<WishlistItem>('POST', `/wishlists/${wishlistId}/items`, {
          ...options,
          body: params,
        }),

      /**
       * Update a wishlist item
       */
      update: (
        wishlistId: string,
        itemId: string,
        params: { quantity: number },
        options?: RequestOptions,
      ): Promise<WishlistItem> =>
        this.request<WishlistItem>('PATCH', `/wishlists/${wishlistId}/items/${itemId}`, {
          ...options,
          body: params,
        }),

      /**
       * Remove an item from a wishlist
       */
      delete: (wishlistId: string, itemId: string, options?: RequestOptions): Promise<void> =>
        this.request<void>('DELETE', `/wishlists/${wishlistId}/items/${itemId}`, options),
    },
  }
}
