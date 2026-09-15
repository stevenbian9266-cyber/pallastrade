import { PallasTradeError } from "@pallastrade/sdk";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import {
  type CartSubmitResult,
  type CheckoutStartBody,
  errorBody,
  errorResponse,
  type PaymentExecution,
  readQuote,
  sameOrigin,
} from "@/lib/checkout/server";
import {
  clearCartCookies,
  getCartOptions,
  getCheckoutOptions,
  getClient,
  setCartCookies,
  setCheckoutCookies,
} from "@/lib/pallastrade";

interface CheckoutCompleteBody {
  order_id: string;
  session_id: string;
}

/**
 * Same-origin checkout BFF. It deliberately avoids Server Actions so converting
 * cart_ → or_ cannot trigger an RSC refresh that redirects away before Stripe
 * confirmation. The browser never receives SDK credentials or guest tokens.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      errorBody("invalid_checkout_origin", "Invalid checkout origin"),
      { status: 403 },
    );
  }

  let submitted: CartSubmitResult | undefined;
  try {
    const body = (await request.json()) as CheckoutStartBody;
    if (!body.payment_method_id) {
      return NextResponse.json(
        errorBody("invalid_request", "Invalid checkout request"),
        { status: 400 },
      );
    }

    const client = getClient();

    // ── 形态 1（两段语义，PRD-20260915 FR-003）：Prepare 已建单 → **只做 Pay** ──
    // 金额权威来自 Order；版本不符时后端返回 409，由页面做页内差异确认。
    if (body.order_id) {
      const orderId = body.order_id;
      if (body.session_required === false) {
        // 非会话类（Check / Store Credit 等）：不启动交易，保持既有语义。
        return NextResponse.json({
          order: { id: orderId },
          transaction: null,
          session: null,
          quote: await readQuote(orderId),
        });
      }

      const started = await client.orders.transactions.create(
        orderId,
        {
          payment_method_id: body.payment_method_id,
          ...(body.payment_mode
            ? { external_data: { mode: body.payment_mode } }
            : {}),
          ...(typeof body.expected_checkout_version === "number"
            ? { expected_checkout_version: body.expected_checkout_version }
            : {}),
          ...(typeof body.expected_price_version === "string" &&
          body.expected_price_version.length > 0
            ? { expected_price_version: body.expected_price_version }
            : {}),
        },
        await getCheckoutOptions(orderId),
      );

      return NextResponse.json({
        order: { id: orderId, state: started.state },
        transaction: { id: started.id, state: started.state },
        session: started.payment_execution,
        quote: await readQuote(orderId),
      });
    }

    // ── 形态 2（兼容）：cart_ 一次请求完成 update + submit + Pay（钱包等入口）──
    // 钱包（Apple Pay / Google Pay）面板自身即金额确认界面，故保留合并语义。
    if (!body.cart_id || !body.checkout) {
      return NextResponse.json(
        errorBody("invalid_request", "Invalid checkout request"),
        { status: 400 },
      );
    }

    const options = await getCartOptions();
    const cart = await client.carts.update(
      body.cart_id,
      body.checkout,
      options,
    );
    const method = cart.payment_methods?.find(
      (candidate) => candidate.id === body.payment_method_id,
    );
    if (!method) {
      return NextResponse.json(
        errorBody(
          "payment_method_unavailable",
          "Payment method is not available",
        ),
        { status: 422 },
      );
    }

    const submittedOrder = (await client.carts.submit(
      body.cart_id,
      options,
    )) as CartSubmitResult;
    submitted = submittedOrder;
    await setCheckoutCookies(submittedOrder.id, cart.token);

    if (submittedOrder.successor_cart) {
      await setCartCookies(
        submittedOrder.successor_cart.id,
        submittedOrder.successor_cart.token,
      );
    } else {
      await clearCartCookies();
    }

    // TXN-P2-6 (轮3, P2 §42/§57): payment-session-first → transaction-first。
    // 会话创建由 orders.transactions.create 承担（后端 Transactions::Start：
    // quote 同意/幂等/快照冻结 + PaymentSessions::Start 绑定 transaction_id）；
    // 返回的 payment_execution 即该 transaction 的支付 attempt（ps_，AC-2006）。
    // PATCH complete 仍走 orders.paymentSessions.complete（下方保持不变）。
    let session: PaymentExecution | null = null;
    let transaction: { id: string; state: string } | null = null;
    if (method.session_required) {
      const started = await client.orders.transactions.create(
        submittedOrder.id,
        {
          payment_method_id: method.id,
          ...(body.payment_mode
            ? { external_data: { mode: body.payment_mode } }
            : {}),
          // PRD-20260914-checkout-quote-confirmation-loop FR-001：把客户端所见报价
          // 版本交给后端（Transactions::Start / PaymentSessions::Start 判定漂移）。
          ...(typeof body.expected_checkout_version === "number"
            ? { expected_checkout_version: body.expected_checkout_version }
            : {}),
          ...(typeof body.expected_price_version === "string" &&
          body.expected_price_version.length > 0
            ? { expected_price_version: body.expected_price_version }
            : {}),
        },
        await getCheckoutOptions(submittedOrder.id),
      );
      transaction = { id: started.id, state: started.state };
      session = started.payment_execution;
    }

    const { successor_cart: _successorCart, ...order } = submittedOrder;
    // FR-002：成功也回传当前报价，前端据此存快照（下次点击携带 expected_*）。
    return NextResponse.json({
      order,
      transaction,
      session,
      quote: await readQuote(submittedOrder.id),
    });
  } catch (error) {
    // FR-003：报价冲突时附带当前报价（读取失败则省略，不改变错误码/状态）。
    const code = error instanceof PallasTradeError ? error.code : undefined;
    const quote =
      submitted?.id &&
      (code === "quote_changed" || code === "checkout_version_conflict")
        ? await readQuote(submitted.id)
        : null;
    return errorResponse(error, submitted?.id, quote);
  }
}

/** Complete a provider-confirmed session using the short-lived checkout token. */
export async function PATCH(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      errorBody("invalid_checkout_origin", "Invalid checkout origin"),
      { status: 403 },
    );
  }

  try {
    const body = (await request.json()) as CheckoutCompleteBody;
    if (!body.order_id || !body.session_id) {
      return NextResponse.json(
        errorBody("invalid_request", "Invalid payment completion request"),
        { status: 400 },
      );
    }

    const session = await getClient().orders.paymentSessions.complete(
      body.order_id,
      body.session_id,
      undefined,
      await getCheckoutOptions(body.order_id),
    );
    return NextResponse.json({ session });
  } catch (error) {
    return errorResponse(error);
  }
}
