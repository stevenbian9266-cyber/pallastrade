import { R as RequestFn, L as LoginCredentials, A as AuthTokens, a as RequestOptions, P as ProductListParams, b as PaginatedResponse, c as Product, d as ProductFiltersParams, e as ProductFiltersResponse, C as CategoryListParams, f as Category, g as ListResponse, h as Country, i as Currency, j as Locale, k as Policy, l as ListParams, m as Post, M as Market, n as Cart, o as CreateCartParams, U as UpdateCartParams, O as Order, p as AddLineItemParams, q as UpdateLineItemParams, r as CreatePaymentParams, s as Payment, t as CreatePaymentSessionParams, u as PaymentSession, v as UpdatePaymentSessionParams, w as CompletePaymentSessionParams, D as DeliveryMethod, x as RegisterParams, y as CreatePaymentCombinationParams, z as PaymentCombination, N as NewsletterSubscriber, B as Customer, E as Address, F as AddressParams, G as CreditCard, H as GiftCard, S as StoreCredit, I as OrderListParams, J as CreatePaymentSetupSessionParams, K as PaymentSetupSession, Q as CompletePaymentSetupSessionParams, T as RequestPasswordResetParams, V as ResetPasswordParams, W as Wishlist, X as WishlistItem, Y as RetryConfig } from './index-BzkjRPGk.cjs';
export { Z as AvailabilityFilter, _ as BackInStockSubscription, $ as Base, a0 as CartItem, a1 as CartWarning, a2 as CategoryFilter, a3 as CategoryFilterOption, a4 as CheckoutRequirement, a5 as ContactMessage, a6 as CustomField, a7 as DeliveryRate, a8 as Digital, a9 as DigitalLink, aa as Discount, ab as EmailPasswordLogin, ac as ErrorResponse, ad as FilterOption, ae as Fulfillment, af as GiftCardBatch, ag as Invitation, ah as LineItem, ai as LineItemInput, aj as LocaleDefaults, ak as Media, al as OptionFilter, am as OptionFilterOption, an as OptionType, ao as OptionValue, ap as PaginationMeta, aq as PallasTradeError, ar as PaymentMethod, as as PaymentSource, at as Price, au as PriceRangeFilter, av as ProductFilter, aw as Promotion, ax as ProviderLogin, ay as Refund, az as ReturnAuthorization, aA as ReturnItem, aB as ShoppingCart, aC as ShoppingCartStatus, aD as SortOption, aE as State, aF as StockLocation, aG as UpdateCartItemParams, aH as Variant } from './index-BzkjRPGk.cjs';

declare class StoreClient {
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
    readonly request: RequestFn;
    constructor(request: RequestFn);
    readonly auth: {
        /**
         * Login with email and password
         */
        login: (credentials: LoginCredentials) => Promise<AuthTokens>;
        /**
         * Refresh access token using a refresh token.
         * Returns new access JWT + rotated refresh token.
         * No Authorization header needed — uses refresh_token in body.
         */
        refresh: (params: {
            refresh_token: string;
        }, options?: RequestOptions) => Promise<AuthTokens>;
        /**
         * Logout — revokes the refresh token.
         */
        logout: (params: {
            refresh_token: string;
        }, options?: RequestOptions) => Promise<void>;
    };
    readonly products: {
        /**
         * List products
         */
        list: (params?: ProductListParams, options?: RequestOptions) => Promise<PaginatedResponse<Product>>;
        /**
         * Get a product by ID or slug
         */
        get: (idOrSlug: string, params?: {
            expand?: string[];
            fields?: string[];
        }, options?: RequestOptions) => Promise<Product>;
        /**
         * Get available filters for products
         * Returns filter options (price range, availability, option types, categories) with counts
         */
        filters: (params?: ProductFiltersParams, options?: RequestOptions) => Promise<ProductFiltersResponse>;
        /**
         * Product reviews (P0-4).
         * `list` returns approved reviews (guest-accessible); `create` submits a
         * review as the signed-in customer (pass a JWT via `options.token`).
         */
        reviews: {
            list: (productId: string, params?: {
                fields?: string[];
            }, options?: RequestOptions) => Promise<Array<{
                id: string;
                product_id: string | null;
                user_name: string | null;
                rating: number;
                title: string | null;
                body: string | null;
                verified_purchase: boolean;
                created_at: string | null;
            }>>;
            create: (productId: string, params: {
                rating: number;
                title?: string;
                body?: string;
            }, options?: RequestOptions) => Promise<{
                id: string;
                product_id: string | null;
                user_name: string | null;
                rating: number;
                title: string | null;
                body: string | null;
                verified_purchase: boolean;
                created_at: string | null;
            }>;
        };
    };
    readonly categories: {
        /**
         * List categories
         */
        list: (params?: CategoryListParams, options?: RequestOptions) => Promise<PaginatedResponse<Category>>;
        /**
         * Get a category by ID or permalink
         */
        get: (idOrPermalink: string, params?: {
            expand?: string[];
            fields?: string[];
        }, options?: RequestOptions) => Promise<Category>;
    };
    readonly countries: {
        /**
         * List countries available in the store
         * Each country includes currency and default_locale derived from its market
         */
        list: (options?: RequestOptions) => Promise<ListResponse<Country>>;
        /**
         * Get a country by ISO code
         * Use `?expand=states` to expand states for address forms
         * @param iso - ISO 3166-1 alpha-2 code (e.g., "US", "DE")
         */
        get: (iso: string, params?: {
            expand?: string[];
            fields?: string[];
        }, options?: RequestOptions) => Promise<Country>;
    };
    readonly currencies: {
        /**
         * List currencies supported by the store (derived from markets)
         */
        list: (options?: RequestOptions) => Promise<ListResponse<Currency>>;
    };
    readonly locales: {
        /**
         * List locales supported by the store (derived from markets)
         */
        list: (options?: RequestOptions) => Promise<ListResponse<Locale>>;
    };
    readonly policies: {
        /**
         * List store policies (return policy, privacy policy, terms of service, etc.)
         */
        list: (options?: RequestOptions) => Promise<ListResponse<Policy>>;
        /**
         * Get a policy by slug or prefixed ID
         * @param id - Policy slug (e.g., 'return-policy') or prefixed ID (e.g., 'pol_abc123')
         */
        get: (id: string, options?: RequestOptions) => Promise<Policy>;
    };
    readonly posts: {
        /**
         * List published blog posts (newest first, paginated)
         */
        list: (params?: ListParams, options?: RequestOptions) => Promise<PaginatedResponse<Post>>;
        /**
         * Get a published blog post by slug or prefixed ID
         * @param id - Post slug (e.g., 'welcome-to-our-store') or prefixed ID (e.g., 'post_abc123')
         */
        get: (id: string, options?: RequestOptions) => Promise<Post>;
    };
    readonly markets: {
        /**
         * List all markets for the current store
         */
        list: (options?: RequestOptions) => Promise<ListResponse<Market>>;
        /**
         * Get a market by prefixed ID
         * @param id - Market prefixed ID (e.g., "mkt_k5nR8xLq")
         */
        get: (id: string, options?: RequestOptions) => Promise<Market>;
        /**
         * Resolve which market applies for a given country
         * @param country - ISO 3166-1 alpha-2 code (e.g., "DE", "US")
         */
        resolve: (country: string, options?: RequestOptions) => Promise<Market>;
        /**
         * Nested resource: Countries in a market
         */
        countries: {
            /**
             * List countries belonging to a market
             * @param marketId - Market prefixed ID
             */
            list: (marketId: string, options?: RequestOptions) => Promise<ListResponse<Country>>;
            /**
             * Get a country by ISO code within a market
             * @param marketId - Market prefixed ID
             * @param iso - Country ISO code (e.g., "DE")
             */
            get: (marketId: string, iso: string, params?: {
                expand?: string[];
                fields?: string[];
            }, options?: RequestOptions) => Promise<Country>;
        };
    };
    readonly carts: {
        /**
         * List all active (incomplete) carts for the authenticated user
         */
        list: (options?: RequestOptions) => Promise<PaginatedResponse<Cart>>;
        /**
         * Get a cart by prefixed ID
         * @param cartId - Cart prefixed ID (e.g., "cart_abc123")
         */
        get: (cartId: string, options?: RequestOptions) => Promise<Cart>;
        /**
         * Create a new cart
         * @param params - Optional cart parameters (e.g., metadata, items)
         */
        create: (params?: CreateCartParams, options?: RequestOptions) => Promise<Cart>;
        /**
         * Update a cart (email, addresses, special instructions)
         * @param cartId - Cart prefixed ID
         * @param params - Cart update parameters
         */
        update: (cartId: string, params: UpdateCartParams, options?: RequestOptions) => Promise<Cart>;
        /**
         * Delete/abandon a cart
         * @param cartId - Cart prefixed ID
         */
        delete: (cartId: string, options?: RequestOptions) => Promise<void>;
        /**
         * Associate a guest cart with the currently authenticated user
         * @param cartId - Cart prefixed ID
         * @param options - Must include `token` (JWT) for authentication
         */
        associate: (cartId: string, options: RequestOptions) => Promise<Cart>;
        /**
         * Complete the cart and finalize the purchase.
         * Returns an Order (not Cart).
         * @param cartId - Cart prefixed ID
         */
        complete: (cartId: string, options?: RequestOptions) => Promise<Order>;
        /**
         * P1 (2026-08-30): Submit the cart — creates a pending Order (standard flow)
         * from the selected cart items and converts the cart.
         * Returns an Order (not Cart). Client should then navigate to /checkout/[orderId].
         * @param cartId - Cart prefixed ID
         */
        submit: (cartId: string, options?: RequestOptions) => Promise<Order>;
        /**
         * Nested resource: Line items
         */
        items: {
            /**
             * Add an item to the cart.
             * Returns the updated cart with recalculated totals.
             * @param cartId - Cart prefixed ID
             */
            create: (cartId: string, params: AddLineItemParams, options?: RequestOptions) => Promise<Cart>;
            /**
             * Update a line item quantity.
             * Returns the updated cart with recalculated totals.
             * @param cartId - Cart prefixed ID
             */
            update: (cartId: string, lineItemId: string, params: UpdateLineItemParams, options?: RequestOptions) => Promise<Cart>;
            /**
             * Remove a line item from the cart.
             * Returns the updated cart with recalculated totals.
             * @param cartId - Cart prefixed ID
             */
            delete: (cartId: string, lineItemId: string, options?: RequestOptions) => Promise<Cart>;
        };
        /**
         * Nested resource: Discount codes
         */
        discountCodes: {
            /**
             * Apply a discount code to the cart
             * @param cartId - Cart prefixed ID
             * @param code - Promotion discount code to apply (e.g., 'SAVE10')
             */
            apply: (cartId: string, code: string, options?: RequestOptions) => Promise<Cart>;
            /**
             * Remove a discount code from the cart
             * @param cartId - Cart prefixed ID
             * @param code - The discount code string to remove (e.g., 'SAVE10')
             */
            remove: (cartId: string, code: string, options?: RequestOptions) => Promise<Cart>;
        };
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
            apply: (cartId: string, code: string, options?: RequestOptions) => Promise<Cart>;
            /**
             * Remove the applied gift card from the cart
             * @param cartId - Cart prefixed ID
             * @param giftCardId - Gift card prefixed ID (e.g., 'gc_abc123')
             */
            remove: (cartId: string, giftCardId: string, options?: RequestOptions) => Promise<Cart>;
        };
        /**
         * Nested resource: Fulfillments
         */
        fulfillments: {
            /**
             * Select a delivery rate for a specific fulfillment.
             * Returns the updated cart with recalculated totals.
             * @param cartId - Cart prefixed ID
             */
            update: (cartId: string, fulfillmentId: string, params: {
                selected_delivery_rate_id: string;
            }, options?: RequestOptions) => Promise<Cart>;
        };
        /**
         * Nested resource: Payments
         */
        payments: {
            /**
             * Create a payment for a non-session payment method (e.g. Check, Cash on Delivery, Bank Transfer).
             * For session-based payment methods (e.g. Stripe, PayPal), use carts.paymentSessions.create() instead.
             * @param cartId - Cart prefixed ID
             */
            create: (cartId: string, params: CreatePaymentParams, options?: RequestOptions) => Promise<Payment>;
        };
        /**
         * Nested resource: Payment sessions
         */
        paymentSessions: {
            /**
             * Create a payment session for the cart.
             * Delegates to the payment gateway to initialize a provider-specific session.
             * @param cartId - Cart prefixed ID
             */
            create: (cartId: string, params: CreatePaymentSessionParams, options?: RequestOptions) => Promise<PaymentSession>;
            /**
             * Get a payment session by ID
             * @param cartId - Cart prefixed ID
             */
            get: (cartId: string, sessionId: string, options?: RequestOptions) => Promise<PaymentSession>;
            /**
             * Update a payment session.
             * Delegates to the payment gateway to sync changes with the provider.
             * @param cartId - Cart prefixed ID
             */
            update: (cartId: string, sessionId: string, params: UpdatePaymentSessionParams, options?: RequestOptions) => Promise<PaymentSession>;
            /**
             * Complete a payment session.
             * Confirms the payment with the provider, triggering capture/authorization.
             * @param cartId - Cart prefixed ID
             */
            complete: (cartId: string, sessionId: string, params?: CompletePaymentSessionParams, options?: RequestOptions) => Promise<PaymentSession>;
        };
        /**
         * Store credits
         */
        storeCredits: {
            /**
             * Apply store credit to the cart
             * @param cartId - Cart prefixed ID
             */
            apply: (cartId: string, amount?: number, options?: RequestOptions) => Promise<Cart>;
            /**
             * Remove store credit from the cart
             * @param cartId - Cart prefixed ID
             */
            remove: (cartId: string, options?: RequestOptions) => Promise<Cart>;
        };
    };
    readonly shippingMethods: {
        /**
         * List front-end shipping methods (name/description with rate label).
         */
        list: (options?: RequestOptions) => Promise<DeliveryMethod[]>;
    };
    readonly orders: {
        /**
         * Get a completed order by prefixed ID.
         * Accessible via JWT (authenticated users) or guestToken (guests).
         */
        get: (id: string, params?: {
            expand?: string[];
            fields?: string[];
        }, options?: RequestOptions) => Promise<Order>;
        /**
         * P1 (2026-08-30): Nested payment sessions — Checkout 纯支付在订单域创建/完成支付会话。
         * 与 legacy `carts.paymentSessions`（Order 同表购物车）不同，标准流程订单是正式 Order。
         */
        paymentSessions: {
            /**
             * Create a payment session for the order.
             */
            create: (orderId: string, params: CreatePaymentSessionParams, options?: RequestOptions) => Promise<PaymentSession>;
            /**
             * Get a payment session by ID.
             */
            get: (orderId: string, sessionId: string, options?: RequestOptions) => Promise<PaymentSession>;
            /**
             * Complete a payment session (confirm payment with the provider).
             */
            complete: (orderId: string, sessionId: string, params?: CompletePaymentSessionParams, options?: RequestOptions) => Promise<PaymentSession>;
        };
    };
    readonly customers: {
        /**
         * Register a new customer account
         */
        create: (params: RegisterParams) => Promise<AuthTokens>;
    };
    readonly paymentCombinations: {
        /**
         * Create a payment combination: combine multiple unpaid orders into a
         * single checkout payment (amount is server-computed).
         * POST /api/v3/store/payment_combinations
         * @param params - Prefixed order IDs + payment method
         * @returns The created combination (with its payment session for the checkout)
         */
        create: (params: CreatePaymentCombinationParams, options?: RequestOptions) => Promise<PaymentCombination>;
        /**
         * Get a payment combination by ID (for the combined-payment checkout page).
         * GET /api/v3/store/payment_combinations/:id
         */
        get: (id: string, options?: RequestOptions) => Promise<PaymentCombination>;
    };
    readonly newsletterSubscribers: {
        /**
         * Subscribe an email address to the newsletter for the current store.
         * Guests get an unverified record; pass a JWT via `options.token` to link
         * to a customer (auto-verifies when the JWT email matches `params.email`).
         * `redirect_url` is dropped from the webhook payload when it's not in the
         * store's allowed origins.
         */
        create: (params: {
            email: string;
            redirect_url?: string;
        }, options?: RequestOptions) => Promise<NewsletterSubscriber>;
        /**
         * Confirm a pending subscription using the token from the confirmation email.
         */
        verify: (params: {
            token: string;
        }, options?: RequestOptions) => Promise<NewsletterSubscriber>;
    };
    readonly backInStockSubscriptions: {
        /**
         * Subscribe an email to be notified when an out-of-stock product is back in stock.
         */
        create: (productId: string, params: {
            email: string;
        }, options?: RequestOptions) => Promise<{
            id: string;
            email: string;
            status: string;
            product_id: string | null;
            created_at: string;
        }>;
    };
    readonly contactMessages: {
        /**
         * Submit a complaint, feedback or inquiry from the storefront. Guest-accessible.
         * Classified by `kind` and surfaced in the admin Email → Inbox & Feedback page.
         */
        create: (params: {
            kind: "complaint" | "feedback" | "inquiry";
            name?: string;
            email: string;
            subject?: string;
            body: string;
        }, options?: RequestOptions) => Promise<{
            id: string;
            kind: string;
            name: string | null;
            email: string;
            subject: string | null;
            body: string;
            status: string;
            created_at: string;
        }>;
    };
    readonly customer: {
        /**
         * Get current customer profile
         */
        get: (options?: RequestOptions) => Promise<Customer>;
        /**
         * Update current customer profile
         */
        update: (params: {
            first_name?: string;
            last_name?: string;
            email?: string;
            password?: string;
            password_confirmation?: string;
            /** Required when changing email or password */
            current_password?: string;
            accepts_email_marketing?: boolean;
            phone?: string;
            /** Arbitrary key-value metadata (stored, not returned in responses) */
            metadata?: Record<string, unknown>;
        }, options?: RequestOptions) => Promise<Customer>;
        /**
         * Nested resource: Addresses
         */
        addresses: {
            /**
             * List customer addresses
             */
            list: (params?: ListParams, options?: RequestOptions) => Promise<PaginatedResponse<Address>>;
            /**
             * Get an address by ID
             */
            get: (id: string, options?: RequestOptions) => Promise<Address>;
            /**
             * Create an address
             */
            create: (params: AddressParams, options?: RequestOptions) => Promise<Address>;
            /**
             * Update an address
             */
            update: (id: string, params: Partial<AddressParams>, options?: RequestOptions) => Promise<Address>;
            /**
             * Delete an address
             */
            delete: (id: string, options?: RequestOptions) => Promise<void>;
        };
        /**
         * Nested resource: Credit Cards
         */
        creditCards: {
            /**
             * List customer credit cards
             */
            list: (params?: ListParams, options?: RequestOptions) => Promise<PaginatedResponse<CreditCard>>;
            /**
             * Get a credit card by ID
             */
            get: (id: string, options?: RequestOptions) => Promise<CreditCard>;
            /**
             * Delete a credit card
             */
            delete: (id: string, options?: RequestOptions) => Promise<void>;
        };
        /**
         * Nested resource: Gift Cards
         */
        giftCards: {
            /**
             * List customer gift cards
             * Returns gift cards associated with the current user, ordered by newest first
             */
            list: (params?: ListParams, options?: RequestOptions) => Promise<PaginatedResponse<GiftCard>>;
            /**
             * Get a gift card by ID
             */
            get: (id: string, options?: RequestOptions) => Promise<GiftCard>;
        };
        /**
         * Nested resource: Store Credits
         */
        storeCredits: {
            /**
             * List store credits for the authenticated customer.
             * Filtered by current store and currency.
             * Supports Ransack filtering (e.g. `q[amount_remaining_gt]: 0`).
             */
            list: (params?: ListParams, options?: RequestOptions) => Promise<PaginatedResponse<StoreCredit>>;
            /**
             * Get a store credit by ID
             */
            get: (id: string, options?: RequestOptions) => Promise<StoreCredit>;
        };
        /**
         * Nested resource: Orders (customer order history)
         */
        orders: {
            /**
             * List completed orders for the authenticated customer
             */
            list: (params?: OrderListParams, options?: RequestOptions) => Promise<PaginatedResponse<Order>>;
            /**
             * Get a completed order by prefixed ID
             */
            get: (id: string, params?: {
                expand?: string[];
                fields?: string[];
            }, options?: RequestOptions) => Promise<Order>;
        };
        /**
         * Nested resource: Payment Setup Sessions (save payment methods for future use)
         */
        paymentSetupSessions: {
            /**
             * Create a payment setup session
             * Delegates to the payment gateway to initialize a setup flow for saving a payment method
             */
            create: (params: CreatePaymentSetupSessionParams, options?: RequestOptions) => Promise<PaymentSetupSession>;
            /**
             * Get a payment setup session by ID
             */
            get: (id: string, options?: RequestOptions) => Promise<PaymentSetupSession>;
            /**
             * Complete a payment setup session
             * Confirms the setup with the provider, resulting in a saved payment method
             */
            complete: (id: string, params?: CompletePaymentSetupSessionParams, options?: RequestOptions) => Promise<PaymentSetupSession>;
        };
    };
    readonly passwordResets: {
        /**
         * Request a password reset email.
         * Always succeeds (202) to prevent email enumeration.
         */
        create: (params: RequestPasswordResetParams) => Promise<{
            message: string;
        }>;
        /**
         * Reset password using the token from the email.
         * Returns a JWT token on success (auto-login).
         * @param token - Password reset token from the email
         */
        update: (token: string, params: ResetPasswordParams) => Promise<AuthTokens>;
    };
    readonly wishlists: {
        /**
         * List wishlists
         */
        list: (params?: ListParams, options?: RequestOptions) => Promise<PaginatedResponse<Wishlist>>;
        /**
         * Get a wishlist by ID
         */
        get: (id: string, params?: {
            expand?: string[];
            fields?: string[];
        }, options?: RequestOptions) => Promise<Wishlist>;
        /**
         * Create a wishlist
         */
        create: (params: {
            name: string;
            is_private?: boolean;
            is_default?: boolean;
        }, options?: RequestOptions) => Promise<Wishlist>;
        /**
         * Update a wishlist
         */
        update: (id: string, params: {
            name?: string;
            is_private?: boolean;
            is_default?: boolean;
        }, options?: RequestOptions) => Promise<Wishlist>;
        /**
         * Delete a wishlist
         */
        delete: (id: string, options?: RequestOptions) => Promise<void>;
        /**
         * Nested resource: Wishlist items
         */
        items: {
            /**
             * Add an item to a wishlist
             */
            create: (wishlistId: string, params: {
                variant_id: string;
                quantity?: number;
            }, options?: RequestOptions) => Promise<WishlistItem>;
            /**
             * Update a wishlist item
             */
            update: (wishlistId: string, itemId: string, params: {
                quantity: number;
            }, options?: RequestOptions) => Promise<WishlistItem>;
            /**
             * Remove an item from a wishlist
             */
            delete: (wishlistId: string, itemId: string, options?: RequestOptions) => Promise<void>;
        };
    };
}

interface ClientConfig {
    /** Base URL of the PallasTrade API (e.g., 'https://api.mystore.com') */
    baseUrl: string;
    /** Publishable API key for Store API access */
    publishableKey: string;
    /** Custom fetch implementation (optional, defaults to global fetch) */
    fetch?: typeof fetch;
    /** Retry configuration. Enabled by default. Pass false to disable. */
    retry?: RetryConfig | false;
    /** Default locale for API requests (e.g., 'fr') */
    locale?: string;
    /** Default currency for API requests (e.g., 'EUR') */
    currency?: string;
    /** Default country ISO code for market resolution (e.g., 'FR') */
    country?: string;
    /** Default channel code (e.g., 'pos', 'wholesale') sent as X-PallasTrade-Channel */
    channel?: string;
}
interface Client extends StoreClient {
    /** Set default locale for all subsequent requests */
    setLocale(locale: string): void;
    /** Set default currency for all subsequent requests */
    setCurrency(currency: string): void;
    /** Set default country for all subsequent requests */
    setCountry(country: string): void;
    /** Set default sales-channel code for all subsequent requests */
    setChannel(channel: string): void;
}
/**
 * Create a new PallasTrade Store SDK client.
 *
 * Returns a flat client with all store resources directly accessible:
 * ```ts
 * const client = createClient({ baseUrl: '...', publishableKey: '...' })
 * client.products.list()
 * client.carts.create()
 * client.orders.get('order_1')
 * ```
 */
declare function createClient(config: ClientConfig): Client;

export { AddLineItemParams, Address, AddressParams, AuthTokens, Cart, Category, CategoryListParams, type Client, type ClientConfig, CompletePaymentSessionParams, CompletePaymentSetupSessionParams, Country, CreateCartParams, CreatePaymentCombinationParams, CreatePaymentParams, CreatePaymentSessionParams, CreatePaymentSetupSessionParams, CreditCard, Currency, Customer, DeliveryMethod, GiftCard, ListParams, ListResponse, Locale, LoginCredentials, Market, NewsletterSubscriber, Order, OrderListParams, PaginatedResponse, Payment, PaymentCombination, PaymentSession, PaymentSetupSession, Policy, Post, Product, ProductFiltersParams, ProductFiltersResponse, ProductListParams, RegisterParams, RequestFn, RequestOptions, RequestPasswordResetParams, ResetPasswordParams, RetryConfig, StoreClient, StoreCredit, UpdateCartParams, UpdateLineItemParams, UpdatePaymentSessionParams, Wishlist, WishlistItem, createClient };
