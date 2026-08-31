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

/** 支付会话的类型（含后端透传的 external_data）。 */
export interface PaymentSessionLike {
  id: string;
  external_data?: Record<string, unknown> | null;
}

/**
 * PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
 * 从支付会话提取 client_secret（位于 external_data 且 URL 编码 %2F → 解码）。
 * 纯函数放非 server 文件（Next.js server action 文件禁止导出非 async 函数），
 * UnifiedCheckout / OrderPaymentContent / PaymentCheckoutModal 三处共用。
 */
export function extractSessionClientSecret(
  session: PaymentSessionLike | null | undefined,
): string | null {
  if (!session) return null;
  const raw = session.external_data?.client_secret as string | undefined;
  if (!raw) return null;
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}
