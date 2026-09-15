"use server";

import type { PaymentCombination } from "@pallastrade/sdk";
import { updateTag } from "next/cache";
import { getClient, withAuthRefresh } from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * Creates a payment combination for the given unpaid orders (P5, 2026-08-27).
 * POST /api/v3/store/payment_combinations — server computes the total.
 * PALLAS-CUSTOM (2026-08-29, bugfix): paymentMethodId 可选，缺省时服务端选默认会话类支付方式。
 */
export async function createPaymentCombination(
  orderIds: string[],
  paymentMethodId?: string,
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
 * PRD-20260829-checkout: `expand=orders` 展开成员订单（items + shipping_address），
 * 供合并流程收货步骤/商品明细使用。
 * GET /api/v3/store/payment_combinations/:id
 */
export async function getPaymentCombination(id: string) {
  return actionResult(async () => {
    return withAuthRefresh(async (options) => {
      return getClient().paymentCombinations.get(
        id,
        { expand: ["orders"] },
        options,
      );
    });
  }, "Failed to load payment combination");
}

/**
 * Completes the combined-payment session (P5).
 *
 * PRD-20260915-checkout B4 FR-010：改走 **Order 域** `orders.paymentSessions.complete`
 * —— 后端 `Store::Orders::PaymentSessionsController#complete` 内置组合分支
 * （TXN-P2：txn 化组合 → `Transactions::OnPaymentSuccess`；legacy 组合 → `Complete` 适配器），
 * 因此不再需要 legacy `carts.paymentSessions.complete`（§45 矩阵 /carts/:id/payment_sessions）。
 *
 * @param orderId 组合主订单（`session.order_id`，会话挂在 primary order 上）
 */
export async function completeCombinationSession(
  orderId: string,
  sessionId: string,
  params?: { session_result?: string },
) {
  return actionResult(async () => {
    const session = await withAuthRefresh(async (options) => {
      return getClient().orders.paymentSessions.complete(
        orderId,
        sessionId,
        params,
        options,
      );
    });
    updateTag("orders");
    return { session };
  }, "Failed to complete payment session");
}
