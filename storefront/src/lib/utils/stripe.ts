import { loadStripe } from "@stripe/stripe-js";

const stripePublishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;

/** Whether Stripe is configured (publishable key present in env). */
export const isStripeConfigured = Boolean(stripePublishableKey);

export const stripePromise = stripePublishableKey
  ? loadStripe(stripePublishableKey)
  : Promise.resolve(null);

/**
 * PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): Checkout Session
 * client_secrets returned by Stripe may carry URL-encoded characters (e.g.
 * `%2F` in the secret segment), which `elements({ clientSecret })` rejects.
 * Normalize before passing to Stripe.js. Idempotent — safe for already-clean
 * secrets (including PaymentIntent `pi_..._secret_...`).
 */
export function normalizeClientSecret(clientSecret: string): string {
  if (!clientSecret.includes("%")) return clientSecret;
  try {
    return decodeURIComponent(clientSecret);
  } catch {
    return clientSecret;
  }
}
