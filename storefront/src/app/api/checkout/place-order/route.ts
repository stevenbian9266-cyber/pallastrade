/**
 * Place Order —— **第一段：建单**（PRD-20260921-checkout-place-order-正名与显式化 FR-001）。
 *
 * 在本 PRD 之前，本实现挂在 `/api/checkout/prepare` 上，名字暗示「预检」，
 * 实际却在做**下单** —— 这正是命名与语义脱节的根源（PRD §1.2）。
 *
 * 做两件事，且**只做**这两件：
 *   1. `carts.update`（保存 email / 地址 / 物流 / 账单语义）
 *   2. `carts.submit`（生成 `or_` 订单 + successor cart）
 * 随后返回 **Order 权威报价**（`quote`）供页面在支付前展示与确认。
 *
 * 明确**不做**：不创建 `PaymentSession`、不启动 `Transaction`
 * （§0.1-2：禁止在用户未见到 Order 权威金额的情况下扣款）。
 *
 * 采用同源 Route Handler（而不是 Server Action），理由与 `/api/checkout/start` 一致：
 * `cart_` → `or_` 的转换不得触发会把用户重定向走的 RSC 刷新。
 *
 * ⚠️ 实现**只能存在一份**：旧路径 `/api/checkout/prepare` 是本文件的**薄别名**
 * （`export { POST } from "../place-order/route"`），不得复制业务逻辑。
 */
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import {
  type CartSubmitResult,
  type CheckoutPlaceOrderBody,
  errorBody,
  errorResponse,
  readQuote,
  sameOrigin,
} from "@/lib/checkout/server";
import {
  clearCartCookies,
  getCartOptions,
  getClient,
  setCartCookies,
  setCheckoutCookies,
} from "@/lib/pallastrade";

export async function POST(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      errorBody("invalid_checkout_origin", "Invalid checkout origin"),
      { status: 403 },
    );
  }

  let submitted: CartSubmitResult | undefined;
  try {
    const body = (await request.json()) as CheckoutPlaceOrderBody;
    if (!body.cart_id || !body.checkout) {
      return NextResponse.json(
        errorBody("invalid_request", "Invalid checkout place order request"),
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

    submitted = (await client.carts.submit(
      body.cart_id,
      options,
    )) as CartSubmitResult;

    // 订单已建立：立刻切换结账令牌/购物车 cookie，保证刷新后上下文是订单而不是旧 cart。
    await setCheckoutCookies(submitted.id, cart.token);
    if (submitted.successor_cart) {
      await setCartCookies(
        submitted.successor_cart.id,
        submitted.successor_cart.token,
      );
    } else {
      await clearCartCookies();
    }

    const { successor_cart: _successorCart, ...order } = submitted;

    return NextResponse.json({
      order_id: submitted.id,
      order,
      // 权威报价：页面据此渲染「最终金额」确认区，并把版本带入 Pay 请求。
      quote: await readQuote(submitted.id),
    });
  } catch (error) {
    // 报价冲突时同样附带当前报价，保证下单阶段的漂移也可页内确认。
    const quote = submitted?.id ? await readQuote(submitted.id) : null;
    return errorResponse(error, submitted?.id, quote);
  }
}
