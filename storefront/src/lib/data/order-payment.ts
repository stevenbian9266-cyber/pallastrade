"use server";

import type { Order } from "@pallastrade/sdk";
import { redirect } from "next/navigation";
import { getCartOptions, getClient } from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * 订单流程标准电商改造 P1（2026-08-30）：订单域支付（Checkout 纯支付）。
 * 与 legacy `lib/data/payment.ts`（cart 域）不同——标准流程订单是正式 Order，
 * 支付会话挂订单（/orders/:id/payment_sessions）。
 */

/** 创建订单支付会话（session-based 支付方式：Stripe/PayPal/Adyen 等）。
 *  PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
 *  `mode: 'payment_intent'` 时后端创建 PaymentIntent（返回 `pi_..._secret`），
 *  供自绘卡字段 `confirmCardPayment` 消费；默认 Checkout Session（PaymentElement）。 */
export async function createOrderPaymentSession(
  orderId: string,
  paymentMethodId: string,
  externalData?: Record<string, unknown>,
  mode?: "payment_intent",
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const session = await getClient().orders.paymentSessions.create(
      orderId,
      {
        payment_method_id: paymentMethodId,
        ...(externalData && { external_data: externalData }),
        ...(mode && {
          external_data: {
            ...(externalData || {}),
            mode,
          },
        }),
      },
      options,
    );
    // PALLAS-CUSTOM (2026-08-31): 不 updateTag("checkout") —— 提交订单后
    // cart 已转 or_ 订单，revalidate 会让 checkout 页服务端 redirect('/cart')
    // 抢先于客户端 router.push（空购物车 bug）。会话创建/完成不改变页面级
    // 展示数据，无需 revalidate。
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
    // PALLAS-CUSTOM (2026-08-31): 不 updateTag("checkout") —— 同 create
    // 注释，revalidate 会触发 checkout 页 redirect('/cart') 竞态。
    return { session };
  }, "Failed to complete payment session");
}

/**
 * 完成订单支付会话 + 完成订单，并由 server action 直接 redirect 到完成页。
 *
 * PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
 * 支付完成后必须由 server action 内 redirect 导航——Next.js 会在每个 server
 * action 完成后自动 refresh 当前路由，若此时 cart 已转订单，checkout 页会
 * 服务端 redirect('/cart') 抢先于客户端 router.push（空购物车 bug）。server
 * action 内的 redirect 是确定性导航，不会被 refresh 竞态抢占。
 */
export async function completeOrderAndRedirectToOrderPlaced(
  orderId: string,
  sessionId: string,
  basePath: string,
) {
  const options = await getCartOptions();
  await getClient().orders.paymentSessions.complete(orderId, sessionId, undefined, options);
  redirect(`${basePath}/order-placed/${orderId}`);
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
