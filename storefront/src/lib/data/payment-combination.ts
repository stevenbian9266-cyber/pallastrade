"use server";

import type { PaymentCombination } from "@pallastrade/sdk";
import { updateTag } from "next/cache";
import { getClient, withAuthRefresh } from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * Creates a payment combination for the given unpaid orders (P5, 2026-08-27).
 * POST /api/v3/store/payment_combinations — server computes the total.
 */
export async function createPaymentCombination(
  orderIds: string[],
  paymentMethodId: string,
): Promise<{ combination: PaymentCombination } | { error: string }> {
  return actionResult(async () => {
    const combination = await withAuthRefresh(async (options) => {
      return getClient().paymentCombinations.create(
        { order_ids: orderIds, payment_method_id: paymentMethodId },
        options,
      );
    });
    updateTag("orders");
    return { combination };
  }, "Failed to create payment combination");
}

/**
 * Loads a payment combination by prefixed ID (P5).
 * GET /api/v3/store/payment_combinations/:id
 */
export async function getPaymentCombination(id: string) {
  return actionResult(async () => {
    return withAuthRefresh(async (options) => {
      return getClient().paymentCombinations.get(id, options);
    });
  }, "Failed to load payment combination");
}

/**
 * Completes the combined-payment session (P5).
 * PATCH /api/v3/store/carts/:cart_id/payment_sessions/:id/complete
 * — when the session belongs to a combination, the backend completes all member
 * orders (PaymentCombinations::Complete).
 */
export async function completeCombinationSession(
  cartId: string,
  sessionId: string,
  params?: { session_result?: string },
) {
  return actionResult(async () => {
    const session = await withAuthRefresh(async (options) => {
      return getClient().carts.paymentSessions.complete(
        cartId,
        sessionId,
        params,
        options,
      );
    });
    updateTag("orders");
    return { session };
  }, "Failed to complete payment session");
}
