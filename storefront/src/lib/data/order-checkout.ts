"use server";

import type { CheckoutUpdateParams, CheckoutView } from "@pallastrade/sdk";
import { PallasTradeError } from "@pallastrade/sdk";
import { getCheckoutOptions, getClient } from "@/lib/pallastrade";

/**
 * CHK-P1-4 (2026-09-03): Order-domain CheckoutView read layer.
 *
 * Wraps `GET /api/v3/store/orders/:order_id/checkout` (OrderCheckout server
 * projection: money/items/addresses + version/price_version/expires_at +
 * ready/missing_requirements). Same ownership/token auth as `getOrderForCheckout`.
 *
 * Returns `null` on any failure so callers can fall back to the Order snapshot —
 * the projection is an enhancement, never a hard dependency of the pay page.
 */
export async function getOrderCheckout(
  orderId: string,
): Promise<CheckoutView | null> {
  try {
    const options = await getCheckoutOptions(orderId);
    return await getClient().orders.checkout.get(orderId, options);
  } catch {
    return null;
  }
}

export type UpdateOrderCheckoutResult =
  | { success: true; view: CheckoutView }
  | { success: false; code?: string; error: string };

/**
 * CHK-P1-4B (2026-09-04): update order checkout (mutation facade).
 * PATCH /orders/:id/checkout — contact / shipping_address(_id) / delivery_rate_id
 * one per call. Returns the server's latest CheckoutView; structured errors
 * (e.g. checkout_version_conflict / validation) surface `code` for the UI.
 */
export async function updateOrderCheckout(
  orderId: string,
  params: CheckoutUpdateParams,
): Promise<UpdateOrderCheckoutResult> {
  try {
    const options = await getCheckoutOptions(orderId);
    const view = await getClient().orders.checkout.update(
      orderId,
      params,
      options,
    );
    return { success: true, view };
  } catch (error) {
    return {
      success: false,
      code: error instanceof PallasTradeError ? error.code : undefined,
      error:
        error instanceof Error ? error.message : "Failed to update checkout",
    };
  }
}
