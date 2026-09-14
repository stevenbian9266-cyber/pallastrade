import {
  type AddressParams,
  type Order,
  type OrderTransactionStart,
  PallasTradeError,
  type ShoppingCart,
} from "@pallastrade/sdk";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import {
  clearCartCookies,
  getCartOptions,
  getCheckoutOptions,
  getClient,
  setCartCookies,
  setCheckoutCookies,
} from "@/lib/pallastrade";

interface CheckoutStartBody {
  cart_id: string;
  payment_method_id: string;
  payment_mode?: "payment_intent";
  /** PRD-20260914-checkout-quote-confirmation-loop FR-001：客户端所见报价版本（可选） */
  expected_checkout_version?: number;
  expected_price_version?: string;
  checkout: {
    email?: string;
    shipping_address?: AddressParams;
    shipping_method_id?: string;
    /** 独立账单地址（取消 "Same as shipping" 时提供） */
    billing_address?: AddressParams;
    /** 账单地址语义（PRD-20260913-checkout-billing-mode）：same_as_shipping | custom */
    billing_mode?: "same_as_shipping" | "custom";
    /** @deprecated 改用 billing_mode（保留以兼容旧客户端） */
    use_shipping?: boolean;
  };
}

interface CheckoutCompleteBody {
  order_id: string;
  session_id: string;
}

type CartSubmitResult = Order & { successor_cart: ShoppingCart | null };

/** TXN-P2-6 (轮3): transactions.create 返回的 payment execution（ps_ 会话）。 */
type PaymentExecution = NonNullable<OrderTransactionStart["payment_execution"]>;

function sameOrigin(request: NextRequest): boolean {
  const origin = request.headers.get("origin");
  if (!origin) return false;

  const forwardedHost = request.headers.get("x-forwarded-host");
  const requestHost = forwardedHost ?? request.headers.get("host");
  if (!requestHost) return false;

  try {
    return new URL(origin).host === requestHost;
  } catch {
    return false;
  }
}

/**
 * 统一错误信封（与后端 v3 error envelope 对齐，见 pallastrade-api-v3 skill）：
 *   { error: { code: string, message: string }, order_id?: string }
 * order_id 保留在顶层供前端失败恢复导航（订单安全可重试）。
 * 前端 UI 一律经 `lib/errors.ts#normalizeErrorMessage` 取 message，禁止直传对象。
 */
function errorBody(
  code: string,
  message: string,
  orderId?: string,
  quote?: unknown,
): {
  error: { code: string; message: string };
  order_id?: string;
  quote?: unknown;
} {
  const body: {
    error: { code: string; message: string };
    order_id?: string;
    quote?: unknown;
  } = {
    error: { code, message },
  };
  if (orderId) body.order_id = orderId;
  // PRD-20260914-checkout-quote-confirmation-loop FR-003：报价冲突时回传当前报价，
  // 供 cart_ 页做页内差异确认（而不是把用户抛到另一个页面）。
  if (quote) body.quote = quote;
  return body;
}

/**
 * INV-P3-6 (FR-049/050): 透传后端结构化业务错误码（INSUFFICIENT_STOCK /
 * INVENTORY_CHANGED / RESERVATION_EXPIRED / INVENTORY_RECOVERY_REQUIRED /
 * quote_changed / transaction_not_payable 等）与后端 HTTP 状态；Storefront 不自行
 * 判断库存，只消费 Server 权威 code/message（订单保持安全可重试）。
 */
function errorResponse(
  error: unknown,
  orderId?: string,
  quote?: unknown,
): NextResponse {
  if (error instanceof PallasTradeError) {
    return NextResponse.json(
      errorBody(error.code || "checkout_failed", error.message, orderId, quote),
      { status: error.status || 422 },
    );
  }

  console.error("checkout orchestration failed", error);
  return NextResponse.json(
    errorBody(
      "checkout_failed",
      "Checkout could not be completed. Your order is safe to retry.",
      orderId,
      quote,
    ),
    { status: orderId ? 502 : 422 },
  );
}

/**
 * PRD-20260914-checkout-quote-confirmation-loop：订单当前报价（供快照 + 409 差异）。
 * 读取失败返回 null —— 报价确认是增强能力，不得改变主流程结果。
 */
async function readQuote(
  orderId: string,
): Promise<Record<string, unknown> | null> {
  try {
    const view = (await getClient().orders.checkout.get(
      orderId,
      await getCheckoutOptions(orderId),
    )) as unknown as Record<string, unknown>;
    const text = (value: unknown) =>
      typeof value === "string" && value.length > 0 ? value : null;

    return {
      checkout_version: typeof view.version === "number" ? view.version : null,
      price_version: text(view.price_version),
      delivery_total: text(view.delivery_total),
      display_delivery_total: text(view.display_delivery_total),
      discount_total: text(view.discount_total),
      display_discount_total: text(view.display_discount_total),
      amount_due: text(view.amount_due),
      display_amount_due: text(view.display_amount_due),
    };
  } catch {
    return null;
  }
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
    if (!body.cart_id || !body.payment_method_id || !body.checkout) {
      return NextResponse.json(
        errorBody("invalid_request", "Invalid checkout request"),
        { status: 400 },
      );
    }

    const client = getClient();
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
