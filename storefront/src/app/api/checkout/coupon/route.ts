import type { Cart } from "@pallastrade/sdk";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { getCartOptions, getClient } from "@/lib/pallastrade";

interface CouponBody {
  cart_id: string;
  /** 折扣码 / 礼品卡代码（apply 时必填） */
  code?: string;
  /** 礼品卡 prefixed id（删除礼品卡时必填，如 gc_xxx） */
  gift_card_id?: string;
  kind: "discount" | "gift_card";
}

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
 * Same-origin BFF for cart discount codes / gift cards (PRD checkout 右栏
 * Order summary 折扣码模块). Keeps SDK credentials + guest cart tokens
 * server-side. Returns the refreshed full Cart so the summary can re-render
 * Subtotal / Discount / Total / TOTAL SAVINGS.
 */
export async function POST(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      { error: "Invalid checkout origin" },
      { status: 403 },
    );
  }

  try {
    const body = (await request.json()) as CouponBody;
    if (!body.cart_id || !body.code || !body.kind) {
      return NextResponse.json(
        { error: "Invalid coupon request" },
        { status: 400 },
      );
    }

    const client = getClient();
    const options = await getCartOptions();

    const cart: Cart =
      body.kind === "gift_card"
        ? await client.carts.giftCards.apply(body.cart_id, body.code, options)
        : await client.carts.discountCodes.apply(
            body.cart_id,
            body.code,
            options,
          );

    return NextResponse.json({ cart });
  } catch (error) {
    console.error("coupon apply failed", error);
    const message =
      error instanceof Error && "status" in error
        ? (error as Error & { status?: number }).status === 404
          ? "Invalid coupon code"
          : "Could not apply coupon. Please try again."
        : "Could not apply coupon. Please try again.";
    return NextResponse.json({ error: message }, { status: 422 });
  }
}

/** Remove an applied discount code or gift card from the cart. */
export async function DELETE(request: NextRequest): Promise<NextResponse> {
  if (!sameOrigin(request)) {
    return NextResponse.json(
      { error: "Invalid checkout origin" },
      { status: 403 },
    );
  }

  try {
    const body = (await request.json()) as CouponBody;
    if (!body.cart_id) {
      return NextResponse.json(
        { error: "Invalid coupon request" },
        { status: 400 },
      );
    }

    const client = getClient();
    const options = await getCartOptions();

    const cart: Cart =
      body.kind === "gift_card"
        ? await client.carts.giftCards.remove(
            body.cart_id,
            body.gift_card_id ?? "",
            options,
          )
        : await client.carts.discountCodes.remove(
            body.cart_id,
            body.code ?? "",
            options,
          );

    return NextResponse.json({ cart });
  } catch (error) {
    console.error("coupon remove failed", error);
    return NextResponse.json(
      { error: "Failed to remove coupon code" },
      { status: 422 },
    );
  }
}
