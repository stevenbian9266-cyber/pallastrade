"use server";

import { updateTag } from "next/cache";
import { getCartOptions, getClient, requireCartId } from "@/lib/pallastrade";
import { getCart } from "./cart";
import { getOrder } from "./orders";
import { actionResult } from "./utils";

export async function createCheckoutPaymentSession(
  cartId: string,
  paymentMethodId: string,
  externalData?: Record<string, unknown>,
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const id = await requireCartId();
    const session = await getClient().carts.paymentSessions.create(
      id,
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

export async function completeCheckoutPaymentSession(
  cartId: string,
  sessionId: string,
  params?: { session_result?: string; external_data?: Record<string, unknown> },
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const id = await requireCartId();
    const session = await getClient().carts.paymentSessions.complete(
      id,
      sessionId,
      params,
      options,
    );
    updateTag("checkout");
    return { session };
  }, "Failed to complete payment session");
}

/**
 * Completes the order by reading server-side truth.
 *
 * CORE-P5-5 (2026-09-06): POST /carts/:id/complete route is gone (404 — replaced by
 * Carts::Submit + orders-domain payment_sessions.complete). Order completion is now
 * server-driven (webhook / Transactions::OnPaymentSuccess); the client must NOT call
 * the dead endpoint. We read server truth instead: a completed order comes back as an
 * Order, anything else (still in flight / unknown) as null — the payment-result page
 * polls and decides the final state.
 */
export async function completeCheckoutOrder(cartId: string) {
  // getOrder never raises (withFallback → null on error).
  const completedOrder = await getOrder(cartId);
  updateTag("checkout");
  updateTag("cart");
  return { success: true as const, order: completedOrder };
}

/**
 * Confirms payment and completes the order after returning from an offsite
 * payment gateway (e.g. CashApp, 3D Secure).
 */
export async function confirmPaymentAndCompleteCart(
  cartId: string,
  sessionId?: string,
  sessionResult?: string,
  redirectResult?: string,
  adyenSessionId?: string,
): Promise<
  { success: true; order: unknown } | { success: false; error: string }
> {
  try {
    // Use explicit cartId — cookies may have been cleared during offsite redirect
    const cart = await getCart(cartId);
    if (!cart) {
      // Cart not found — the order may already be completed (e.g. by webhook).
      // Try fetching it as a completed order before giving up.
      const completedOrder = await getOrder(cartId).catch(() => null);
      return { success: true, order: completedOrder };
    }

    if (cart.current_step === "complete") {
      return { success: true, order: cart };
    }

    if (sessionId) {
      const options = await getCartOptions();
      const id = await requireCartId();
      const completeResult = await getClient().carts.paymentSessions.complete(
        id,
        sessionId,
        sessionResult ? { session_result: sessionResult } : undefined,
        options,
      );
      if (completeResult.status === "failed") {
        return {
          success: false,
          error: "Payment was not successful. Please try again.",
        };
      }
    } else if (redirectResult) {
      // Adyen redirect flow: redirectResult is appended by Adyen to the return URL.
      // Pass it to the backend which resolves the session and processes the redirect.
      const options = await getCartOptions();
      const id = await requireCartId();
      const completeResult = await getClient().carts.paymentSessions.complete(
        id,
        adyenSessionId ?? "",
        {
          external_data: {
            redirect_result: redirectResult,
          },
        },
        options,
      );
      if (completeResult.status === "failed") {
        return {
          success: false,
          error: "Payment was not successful. Please try again.",
        };
      }
    }

    const result = await completeCheckoutOrder(cartId);
    if (result.order) {
      return { success: true, order: result.order };
    }
    // CORE-P5-5：completeCheckoutOrder 恒 success（无失败分支）；order 为 null =
    // 订单仍在处理/未知，统一按确认失败提示（终态由支付结果页轮询决定）。
    return {
      success: false,
      error: "Failed to confirm payment. Please try again.",
    };
  } catch (error) {
    return {
      success: false,
      error:
        error instanceof Error
          ? error.message
          : "Failed to confirm payment. Please try again.",
    };
  }
}
