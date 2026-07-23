import { createHmac, timingSafeEqual } from 'node:crypto'

// ─── Verification ──────────────────────────────────────────────

/**
 * Verifies the HMAC-SHA256 signature of a PallasTrade webhook request.
 *
 * PallasTrade signs webhooks as: HMAC-SHA256(secret, "{timestamp}.{payload}")
 * with headers X-PallasTrade-Webhook-Signature and X-PallasTrade-Webhook-Timestamp.
 *
 * @param payload - Raw request body string
 * @param signature - Value of X-PallasTrade-Webhook-Signature header
 * @param timestamp - Value of X-PallasTrade-Webhook-Timestamp header
 * @param secret - The webhook endpoint's secret key
 * @param toleranceSeconds - Max age of the timestamp in seconds (default: 300 = 5 min)
 *
 * @example
 * ```ts
 * import { verifyWebhookSignature } from '@pallastrade/sdk/webhooks'
 *
 * const isValid = verifyWebhookSignature(
 *   rawBody,
 *   request.headers['x-pallastrade-webhook-signature'],
 *   request.headers['x-pallastrade-webhook-timestamp'],
 *   process.env.PALLASTRADE_WEBHOOK_SECRET
 * )
 * ```
 */
export function verifyWebhookSignature(
  payload: string,
  signature: string,
  timestamp: string,
  secret: string,
  toleranceSeconds = 300,
): boolean {
  const ts = Number.parseInt(timestamp, 10)
  if (Number.isNaN(ts)) return false

  const age = Math.abs(Math.floor(Date.now() / 1000) - ts)
  if (age > toleranceSeconds) return false

  const expected = createHmac('sha256', secret).update(`${timestamp}.${payload}`).digest('hex')

  try {
    return timingSafeEqual(Buffer.from(signature), Buffer.from(expected))
  } catch {
    return false
  }
}

// ─── Types ─────────────────────────────────────────────────────

/**
 * PallasTrade webhook event envelope.
 *
 * The `data` field contains the serialized resource using the same
 * Store API V3 serializers as the REST API. Use the SDK's existing types
 * (e.g. `Cart`, `Order`, `Payment`, `Fulfillment`) for the `data` field.
 *
 * @example
 * ```ts
 * import type { WebhookEvent } from '@pallastrade/sdk/webhooks'
 * import type { Order, Payment } from '@pallastrade/sdk'
 *
 * // Order events (order.completed, order.canceled, etc.)
 * type OrderEvent = WebhookEvent<Order>
 *
 * // Payment events (payment.paid, etc.)
 * type PaymentEvent = WebhookEvent<Payment>
 *
 * // Custom event with ad-hoc payload
 * type PasswordResetEvent = WebhookEvent<{ email: string; reset_token: string }>
 * ```
 */
export interface WebhookEvent<T = unknown> {
  id: string
  name: string
  created_at: string
  data: T
  metadata: {
    pallastrade_version: string
  }
}
