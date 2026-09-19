/**
 * PRD-20260919-shipping-checkout-quote-preview —— 结算页**只读预览报价** BFF。
 *
 * 与 `/api/checkout/prepare` / `start` 同模式（同源 Route Handler，不触发 RSC 刷新）：
 *   - 服务端调用 SDK `carts.previewQuote`（dry-run 同源管线），**不建单、不写库**；
 *   - 前端只拿估算金额与方法集合，用于首屏默认选中与右栏金额；
 *   - 权威金额仍来自 `prepare` 建单后的报价（本路由不参与支付链路）。
 */
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { errorBody, sameOrigin } from "@/lib/checkout/server";
import { getCartOptions, getClient } from "@/lib/pallastrade";

export interface CheckoutPreviewBody {
  cart_id?: string;
  /** header 国家（ISO）：无地址时的临时地址来源 */
  country?: string;
  shipping_method_id?: string;
  shipping_address?: Record<string, string | null | undefined>;
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      errorBody("invalid_checkout_origin", "Invalid checkout origin"),
      { status: 403 },
    );
  }

  let body: CheckoutPreviewBody;
  try {
    body = (await request.json()) as CheckoutPreviewBody;
  } catch {
    return NextResponse.json(errorBody("invalid_request", "Invalid JSON"), {
      status: 400,
    });
  }

  if (!body.cart_id) {
    return NextResponse.json(
      errorBody("invalid_request", "cart_id is required"),
      { status: 400 },
    );
  }

  try {
    const client = getClient();
    const options = await getCartOptions();
    const preview = await client.carts.previewQuote(
      body.cart_id,
      {
        country: body.country,
        shipping_method_id: body.shipping_method_id,
        shipping_address: body.shipping_address,
      },
      options,
    );
    return NextResponse.json(preview);
  } catch (error) {
    // 预览失败必须可降级：前端回落到既有「提交时计算」标注，不得阻塞结算。
    return NextResponse.json(
      errorBody(
        "preview_unavailable",
        error instanceof Error ? error.message : "Preview unavailable",
      ),
      { status: 502 },
    );
  }
}
