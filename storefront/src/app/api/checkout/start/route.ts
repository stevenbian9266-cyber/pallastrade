import type {
  AddressParams,
  Order,
  OrderTransactionStart,
  ShoppingCart,
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
  checkout: {
    email?: string;
    shipping_address?: AddressParams;
    shipping_method_id?: string;
    /** 独立账单地址（取消 "Same as shipping" 时提供） */
    billing_address?: AddressParams;
    /** 复用配送地址作为账单地址（默认 true） */
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

function errorResponse(error: unknown, orderId?: string): NextResponse {
  console.error("checkout orchestration failed", error);
  return NextResponse.json(
    {
      error: "Checkout could not be completed. Your order is safe to retry.",
      ...(orderId && { order_id: orderId }),
    },
    { status: orderId ? 502 : 422 },
  );
}

/**
 * Same-origin checkout BFF. It deliberately avoids Server Actions so converting
 * cart_ → or_ cannot trigger an RSC refresh that redirects away before Stripe
 * confirmation. The browser never receives SDK credentials or guest tokens.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      { error: "Invalid checkout origin" },
      { status: 403 },
    );
  }

  let submitted: CartSubmitResult | undefined;
  try {
    const body = (await request.json()) as CheckoutStartBody;
    if (!body.cart_id || !body.payment_method_id || !body.checkout) {
      return NextResponse.json(
        { error: "Invalid checkout request" },
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
        { error: "Payment method is not available" },
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
        },
        await getCheckoutOptions(submittedOrder.id),
      );
      transaction = { id: started.id, state: started.state };
      session = started.payment_execution;
    }

    const { successor_cart: _successorCart, ...order } = submittedOrder;
    return NextResponse.json({ order, transaction, session });
  } catch (error) {
    return errorResponse(error, submitted?.id);
  }
}

/** Complete a provider-confirmed session using the short-lived checkout token. */
export async function PATCH(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      { error: "Invalid checkout origin" },
      { status: 403 },
    );
  }

  try {
    const body = (await request.json()) as CheckoutCompleteBody;
    if (!body.order_id || !body.session_id) {
      return NextResponse.json(
        { error: "Invalid payment completion request" },
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
