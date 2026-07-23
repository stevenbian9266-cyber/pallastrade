export interface PallasTradeNextConfig {
  /** Base URL of the PallasTrade API (e.g., 'https://api.mystore.com') */
  baseUrl: string;
  /** Publishable API key for Store API access */
  publishableKey: string;
  /** Cookie name for the cart order token (default: '_pallastrade_cart_token') */
  cartCookieName?: string;
  /** Cookie name for the JWT access token (default: '_pallastrade_jwt') */
  accessTokenCookieName?: string;
  /** Cookie name for country (default: 'pallastrade_country') */
  countryCookieName?: string;
  /** Cookie name for locale (default: 'pallastrade_locale') */
  localeCookieName?: string;
  /** Default locale for API requests */
  defaultLocale?: string;
  /** Default currency for API requests */
  defaultCurrency?: string;
  /** Default country ISO code for market resolution */
  defaultCountry?: string;
}

export interface PallasTradeNextOptions {
  /** Locale for translated content (e.g., 'en', 'fr') */
  locale?: string;
  /** Currency for prices (e.g., 'USD', 'EUR') */
  currency?: string;
  /** Country ISO code for market resolution (e.g., 'US', 'DE') */
  country?: string;
}
