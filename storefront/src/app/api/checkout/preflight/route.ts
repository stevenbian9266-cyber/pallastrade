/**
 * PRD-20260919-checkout —— 补付重验（payment preflight）BFF。
 *
 * 与 `/api/checkout/preview` 同模式（同源 Route Handler，不触发 RSC 刷新）：
 *   - 服务端调用 SDK `orders.paymentPreflight.get`（服务端 dry-run，零副作用）；
 *   - 返回重验后应付金额 / 失效商品 / 金额变化 / 硬阻断原因，供订单支付页渲染；
 *   - 权威金额仍来自 `orders.transactions.create`（写路径复用同一重验实现）。
 * 客户端刷新用（如换配送方式后重新核对）；首屏由 Server Component 直接取。
 */
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { errorBody, sameOrigin } from "@/lib/checkout/server";
import { getCheckoutOptions, getClient } from "@/lib/pallastrade";

export async function GET(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      errorBody("invalid_checkout_origin", "Invalid checkout origin"),
      { status: 403 },
    );
  }

  const orderId = request.nextUrl.searchParams.get("order_id");
  if (!orderId) {
    return NextResponse.json(
      errorBody("invalid_request", "order_id is required"),
      { status: 400 },
    );
  }

  try {
    const client = getClient();
    const options = await getCheckoutOptions(orderId);
    const report = await client.orders.paymentPreflight.get(orderId, options);
    return NextResponse.json(report);
  } catch (error) {
    // 预检失败必须可降级：支付页回落到既有 CheckoutView / Order 快照（不阻塞补付）。
    return NextResponse.json(
      errorBody(
        "preflight_unavailable",
        error instanceof Error ? error.message : "Preflight unavailable",
      ),
      { status: 502 },
    );
  }
}
