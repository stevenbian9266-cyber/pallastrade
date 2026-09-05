"use server";

import type {
  Order,
  OrderTransactionStart,
  PaymentSession,
} from "@pallastrade/sdk";
import { PallasTradeError } from "@pallastrade/sdk";
import { redirect } from "next/navigation";
import { getCheckoutOptions, getClient } from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * 订单流程标准电商改造 P1（2026-08-30）：订单域支付（Checkout 纯支付）。
 * 与 legacy `lib/data/payment.ts`（cart 域）不同——标准流程订单是正式 Order，
 * 支付会话挂订单（/orders/:id/payment_sessions）。
 * TXN-P2-6 轮3（2026-09-05）：会话创建改由 durable CommerceTransaction 启动
 * （orders.transactions.create → Transactions::Start）；payment execution 即会话。
 */

/** TXN-P2-6 (轮3): transactions.create 返回的 payment execution（ps_ 会话）。 */
type PaymentExecution = NonNullable<OrderTransactionStart["payment_execution"]>;

export type CreateOrderPaymentSessionResult =
  | {
      success: true;
      session: PaymentExecution;
      /** durable CommerceTransaction 身份（id/state），供后续 resume/重试。 */
      transaction?: { id: string; state: string };
    }
  | { success: false; code?: string; error: string };

/** 启动 durable CommerceTransaction 并取其支付会话（session-based 支付方式）。
 *  TXN-P2-6 轮3（P2 §42/§57）：payment-session-first → transaction-first——
 *  前端触发支付先 Start Transaction（后端 Transactions::Start：quote 同意/
 *  幂等/快照冻结 + PaymentSessions::Start 绑定 transaction_id），返回的
 *  payment_execution 即该 transaction 的支付 attempt（ps_，AC-2006）。
 *  PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
 *  `mode: 'payment_intent'` 时后端创建 PaymentIntent（返回 `pi_..._secret`），
 *  供自绘卡字段 `confirmCardPayment` 消费；默认 Checkout Session（PaymentElement）。
 *  CHK-P1-4B (2026-09-04): 失败时透传 PallasTradeError.code（如
 *  `checkout_version_conflict`/`quote_changed` 409）供 UI 提示。 */
export async function createOrderPaymentSession(
  orderId: string,
  paymentMethodId: string,
  externalData?: Record<string, unknown>,
  mode?: "payment_intent",
): Promise<CreateOrderPaymentSessionResult> {
  try {
    const options = await getCheckoutOptions(orderId);
    const started = await getClient().orders.transactions.create(
      orderId,
      {
        payment_method_id: paymentMethodId,
        ...(externalData || mode
          ? {
              external_data: {
                ...(externalData || {}),
                ...(mode ? { mode } : {}),
              },
            }
          : {}),
      },
      options,
    );
    const session = started.payment_execution;
    // PALLAS-CUSTOM (2026-08-31): 不 updateTag("checkout") —— 提交订单后
    // cart 已转 or_ 订单，revalidate 会让 checkout 页服务端重定向到购物车页
    // 抢先于客户端 router.push（空购物车 bug）。会话创建/完成不改变页面级
    // 展示数据，无需 revalidate。
    if (!session) {
      return {
        success: false,
        error: "Payment method did not produce a payment session",
      };
    }
    return {
      success: true,
      session,
      transaction: { id: started.id, state: started.state },
    };
  } catch (error) {
    return {
      success: false,
      code: error instanceof PallasTradeError ? error.code : undefined,
      error:
        error instanceof Error
          ? error.message
          : "Failed to create payment session",
    };
  }
}

/** 完成订单支付会话（客户端确认支付后）。 */
export async function completeOrderPaymentSession(
  orderId: string,
  sessionId: string,
  params?: { session_result?: string; external_data?: Record<string, unknown> },
) {
  return actionResult(async () => {
    const options = await getCheckoutOptions(orderId);
    const session = await getClient().orders.paymentSessions.complete(
      orderId,
      sessionId,
      params,
      options,
    );
    // PALLAS-CUSTOM (2026-08-31): 不 updateTag("checkout") —— 同 create
    // 注释，revalidate 会触发 checkout 页与购物车页之间的重定向竞态。
    return { session };
  }, "Failed to complete payment session");
}

/**
 * 完成订单支付会话 + 完成订单，并由 server action 直接 redirect 到完成页。
 *
 * PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
 * 支付完成后必须由 server action 内重定向导航——Next.js 会在每个 server
 * action 完成后自动 refresh 当前路由，若此时 cart 已转订单，checkout 页会
 * 服务端抢先重定向到购物车页（空购物车 bug）。server
 * action 内的重定向是确定性导航，不会被 refresh 竞态抢占。
 */
export async function completeOrderPaymentSessionAndRedirectToResult(
  orderId: string,
  sessionId: string,
  basePath: string,
) {
  const options = await getCheckoutOptions(orderId);
  await getClient().orders.paymentSessions.complete(
    orderId,
    sessionId,
    undefined,
    options,
  );
  redirect(`${basePath}/payment-result/${orderId}?session=${sessionId}`);
}

/** 读取订单（Checkout 支付页）。 */
export async function getOrderForCheckout(
  orderId: string,
): Promise<Order | null> {
  try {
    const options = await getCheckoutOptions(orderId);
    return await getClient().orders.get(orderId, undefined, options);
  } catch {
    return null;
  }
}

/** Read an Order payment session for the server-authoritative result page. */
export async function getOrderPaymentSession(
  orderId: string,
  sessionId: string,
) {
  try {
    const options = await getCheckoutOptions(orderId);
    return await getClient().orders.paymentSessions.get(
      orderId,
      sessionId,
      options,
    );
  } catch {
    return null;
  }
}
