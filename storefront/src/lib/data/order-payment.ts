"use server";

import type { Order } from "@pallastrade/sdk";
import { updateTag } from "next/cache";
import { getCartOptions, getClient } from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * 订单流程标准电商改造 P1（2026-08-30）：订单域支付（Checkout 纯支付）。
 * 与 legacy `lib/data/payment.ts`（cart 域）不同——标准流程订单是正式 Order，
 * 支付会话挂订单（/orders/:id/payment_sessions）。
 */

/** 创建订单支付会话（session-based 支付方式：Stripe/PayPal/Adyen 等）。 */
export async function createOrderPaymentSession(
  orderId: string,
  paymentMethodId: string,
  externalData?: Record<string, unknown>,
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const session = await getClient().orders.paymentSessions.create(
      orderId,
      {
        payment_method_id: paymentMethodId,
        ...(externalData && { external_data: externalData }),
      },
      options,
    );
    updateTag("checkout");
    return { session };
  }, "Failed to create payment session");
}

/** 完成订单支付会话（客户端确认支付后）。 */
export async function completeOrderPaymentSession(
  orderId: string,
  sessionId: string,
  params?: { session_result?: string; external_data?: Record<string, unknown> },
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const session = await getClient().orders.paymentSessions.complete(
      orderId,
      sessionId,
      params,
      options,
    );
    updateTag("checkout");
    return { session };
  }, "Failed to complete payment session");
}

/**
 * 完成标准流程订单（支付成功后触发 Carts::Complete 标准分支：pay! + finalize!）。
 * 403/422 视为已由 webhook 完成。
 */
export async function completeOrder(orderId: string) {
  try {
    const options = await getCartOptions();
    // 标准流程：支付会话完成即驱动订单完成（Carts::Complete）。此处再查一次订单
    // 状态，已 paid/completed 直接返回。
    const order: Order = await getClient().orders.get(
      orderId,
      undefined,
      options,
    );
    return { success: true as const, order };
  } catch (error: unknown) {
    return {
      success: false as const,
      error:
        error instanceof Error ? error.message : "Failed to complete order",
    };
  }
}

/** 读取订单（Checkout 支付页）。 */
export async function getOrderForCheckout(
  orderId: string,
): Promise<Order | null> {
  try {
    const options = await getCartOptions();
    return await getClient().orders.get(orderId, undefined, options);
  } catch {
    return null;
  }
}
