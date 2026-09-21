/**
 * PRD-20260915-checkout-单页两段语义（Prepare → 报价确认 → Pay）：
 * Checkout BFF 共享服务端工具，被 `/api/checkout/prepare`（Prepare）与
 * `/api/checkout/start`（Pay）共用。
 *
 * 契约要点（业务方案 §0.1-1/2）：
 * - **报价权威只有 Order**：Prepare 之后才产生权威金额（税/运/抵扣）；
 * - 报价快照形状与 `lib/checkout-quote.ts` 的 `CheckoutQuote` 一一对应，
 *   金额一律 raw（`amount_due` 等）+ `display_*`（仅渲染），禁止 parseFloat(display_*)。
 */
import {
  type AddressParams,
  type Order,
  type OrderTransactionStart,
  PallasTradeError,
  type ShoppingCart,
} from "@pallastrade/sdk";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { getCheckoutOptions, getClient } from "@/lib/pallastrade";

/**
 * Place Order 请求体（两段语义**第一段：建单**）。产出 Order 权威报价。
 *
 * PRD-20260921-checkout-place-order-正名与显式化 FR-004：由 `CheckoutPrepareBody`
 * 正名而来（`prepare` 名字暗示「预检」，实际在**建单**）。
 */
export interface CheckoutPlaceOrderBody {
  cart_id: string;
  checkout: CheckoutParams;
}

/**
 * @deprecated 旧名 alias（同 PRD FR-004）—— 仅为避免外部引用断裂而保留。
 * 新代码请用 `CheckoutPlaceOrderBody`。
 */
export type CheckoutPrepareBody = CheckoutPlaceOrderBody;

export interface CheckoutParams {
  email?: string;
  shipping_address?: AddressParams;
  shipping_method_id?: string;
  /** 独立账单地址（取消 "Same as shipping" 时提供） */
  billing_address?: AddressParams;
  /** 账单地址语义（PRD-20260913-checkout-billing-mode）：same_as_shipping | custom */
  billing_mode?: "same_as_shipping" | "custom";
  /** @deprecated 改用 billing_mode（保留以兼容旧客户端） */
  use_shipping?: boolean;
}

/**
 * Pay 请求体。两种形态：
 * 1. **两段语义（PRD-20260915 FR-003）**：`order_id` + `payment_method_id` + `expected_*`
 *    —— Prepare 已建单，本请求**只做 Pay**（`orders.transactions.create`）；
 * 2. 兼容形态：`cart_id` + `checkout` —— 由钱包（Express）等入口在一次请求内完成
 *    update + submit + Pay（钱包面板自身即金额确认界面）。
 */
export interface CheckoutStartBody {
  order_id?: string;
  cart_id?: string;
  payment_method_id: string;
  payment_mode?: "payment_intent";
  /**
   * PALLAS-CUSTOM: D7（PRD-20260918-payments-d7-payment-section-express）
   * 支付入口（method kind，如 card / apple_pay / google_pay）——前台按入口选择；
   * 服务端 `PaymentSessions::Start` 用同一入口集合同源复算可用性（可选，缺省 = 默认入口）。
   */
  option_kind?: string;
  /** 该支付方式是否需要向 provider 建会话（前端从 PaymentMethod.session_required 带入）。 */
  session_required?: boolean;
  /** PRD-20260914-checkout-quote-confirmation-loop FR-001：客户端所见报价版本（可选） */
  expected_checkout_version?: number;
  expected_price_version?: string;
  checkout?: CheckoutParams;
}

export type CartSubmitResult = Order & { successor_cart: ShoppingCart | null };

/** TXN-P2-6 (轮3): transactions.create 返回的 payment execution（ps_ 会话）。 */
export type PaymentExecution = NonNullable<
  OrderTransactionStart["payment_execution"]
>;

export function sameOrigin(request: NextRequest): boolean {
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
export function errorBody(
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
export function errorResponse(
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

/** 读取 Order 权威报价（CheckoutView 投影）→ 报价快照形状（raw + display 成对）。 */
export async function readQuote(
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
      // PRD-20260919-checkout-order-summary-fee-read-model FR-007：右栏税费行
      // 需要权威税费（`CheckoutView` 早已下发，此处只是补齐快照形状）。
      tax_total: text(view.tax_total),
      display_tax_total: text(view.display_tax_total),
      amount_due: text(view.amount_due),
      display_amount_due: text(view.display_amount_due),
    };
  } catch {
    return null;
  }
}
