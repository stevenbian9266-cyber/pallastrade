/**
 * Gateway type registry for conditional SDK loading.
 *
 * Maps PallasTrade PaymentMethod.type (API shorthand) to a frontend gateway
 * identifier so the checkout can dynamically import the right SDK component.
 *
 * Only session-based gateways need this mapping. Non-session methods
 * (session_required === false) use the direct payment flow with no SDK.
 */

/** Known gateway identifiers for conditional SDK loading */
export type GatewayId = "stripe" | "adyen" | "paypal" | "razorpay" | "unknown";

/**
 * Map PallasTrade PaymentMethod.type (API shorthand) → frontend gateway ID.
 *
 * The Store API returns `PallasTrade::Gateway.api_type` — for provider gems
 * that ship a top-level `Gateway` class, that's the outer module name
 * stripped of its `PallasTrade` prefix and underscored:
 *
 *   PallasTradeStripe::Gateway          → "stripe"
 *   PallasTradeAdyen::Gateway           → "adyen"
 *   PallasTradePaypalCheckout::Gateway  → "paypal_checkout"
 *   PallasTradeRazorpayCheckout::Gateway → "razorpay_checkout"
 *
 * For gems whose shorthand already matches the frontend ID (`stripe`,
 * `adyen`), the map mostly normalises the suffixed forms. Legacy Rails
 * STI class names are kept for backwards compatibility with older
 * backends that haven't been upgraded yet.
 *
 * Adding a new gateway integration is a single line here.
 */
const GATEWAY_TYPE_MAP: Record<string, GatewayId> = {
  // Stripe (pallastrade_stripe gem)
  stripe: "stripe",
  "PallasTradeStripe::Gateway": "stripe",
  // Adyen (pallastrade_adyen gem)
  adyen: "adyen",
  "PallasTradeAdyen::Gateway": "adyen",
  // PayPal (pallastrade_paypal_checkout gem)
  paypal_checkout: "paypal",
  paypal: "paypal",
  "PallasTradePaypalCheckout::Gateway": "paypal",
  // Razorpay (pallastrade_razorpay_checkout gem)
  razorpay_checkout: "razorpay",
  razorpay: "razorpay",
  "PallasTradeRazorpayCheckout::Gateway": "razorpay",
};

/**
 * Resolve a PallasTrade PaymentMethod.type to a frontend gateway identifier.
 * Returns "unknown" for unrecognised session-based gateways.
 */
export function resolveGatewayId(paymentMethodType: string): GatewayId {
  return GATEWAY_TYPE_MAP[paymentMethodType] ?? "unknown";
}

/** Whether PayPal is configured (client ID present in env). */
export const isPayPalConfigured = Boolean(
  process.env.NEXT_PUBLIC_PAYPAL_CLIENT_ID,
);

/** PayPal client ID for SDK initialization. */
export const paypalClientId = process.env.NEXT_PUBLIC_PAYPAL_CLIENT_ID ?? "";

/** Whether Adyen is configured (client key present in env). */
export const isAdyenConfigured = Boolean(
  process.env.NEXT_PUBLIC_ADYEN_CLIENT_KEY,
);

/** Adyen client key for Drop-in initialization. */
export const adyenClientKey = process.env.NEXT_PUBLIC_ADYEN_CLIENT_KEY ?? "";

/** Adyen environment: "test" or "live". */
const rawAdyenEnv = process.env.NEXT_PUBLIC_ADYEN_ENVIRONMENT;
export const adyenEnvironment: "test" | "live" =
  rawAdyenEnv === "live" ? "live" : "test";
