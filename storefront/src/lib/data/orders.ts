"use server";

import type { OrderListParams } from "@pallastrade/sdk";
import { getCartOptions, getClient, withAuthRefresh } from "@/lib/pallastrade";
import { withFallback } from "./utils";

export async function getOrders(params?: OrderListParams) {
  return withFallback(
    async () => {
      return withAuthRefresh(async (options) => {
        return getClient().customer.orders.list(params, options);
      });
    },
    {
      data: [],
      meta: {
        page: 1,
        limit: 25,
        count: 0,
        pages: 0,
        from: 0,
        to: 0,
        in: 0,
        previous: null,
        next: null,
      },
    },
  );
}

/**
 * PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
 * Lists placed-but-unpaid orders eligible for combined payment.
 */
export async function getUnpaidOrders(limit = 50) {
  return getOrders({ limit, scope: "unpaid" as string } as OrderListParams);
}

/**
 * Get a single order by ID or number.
 * Works for both authenticated users (JWT) and guests (guestToken).
 */
export async function getOrder(id: string, params?: Record<string, unknown>) {
  return withFallback(async () => {
    const options = await getCartOptions();
    return getClient().orders.get(id, params, options);
  }, null);
}
