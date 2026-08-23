"use server";

import type { PaymentGroup } from "@pallastrade/sdk";
import { updateTag } from "next/cache";
import { getCartOptions, getClient } from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * Create a payment group from multiple unpaid order ids.
 * Requires a logged-in customer (JWT via options).
 */
export async function createPaymentGroup(orderIds: string[]) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const group = await getClient().paymentGroups.create(
      { order_ids: orderIds },
      options,
    );
    updateTag("payment-groups");
    return { group };
  }, "Failed to create payment group");
}

/**
 * Get a payment group by id (own groups only).
 */
export async function getPaymentGroup(
  id: string,
  params?: { expand?: string[] },
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const group: PaymentGroup = await getClient().paymentGroups.get(
      id,
      params ? { expand: params.expand } : { expand: ["orders"] },
      options,
    );
    return { group };
  }, "Failed to load payment group");
}

/**
 * Create a payment session covering the whole payment group.
 */
export async function createGroupPaymentSession(
  groupId: string,
  paymentMethodId: string,
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const session = await getClient().paymentGroups.paymentSessions.create(
      groupId,
      { payment_method_id: paymentMethodId },
      options,
    );
    updateTag("payment-groups");
    return { session };
  }, "Failed to create payment session");
}

/**
 * Complete a payment session of the group (called after Stripe confirms).
 */
export async function completeGroupPaymentSession(
  groupId: string,
  sessionId: string,
  params?: { session_result?: string },
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const session = await getClient().paymentGroups.paymentSessions.complete(
      groupId,
      sessionId,
      params,
      options,
    );
    updateTag("payment-groups");
    return { session };
  }, "Failed to complete payment session");
}
