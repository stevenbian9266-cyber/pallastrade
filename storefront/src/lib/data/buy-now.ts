"use server";

import { updateTag } from "next/cache";
import {
  getCartId,
  getCartOptions,
  getClient,
  setCartCookies,
} from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * Buy Now（P5, 2026-08-27）：创建含当前商品的独立 cart 并直接进入确认页，
 * 不污染既有购物车。
 */
export async function createBuyNowCart(variantId: string, quantity = 1) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const previousCartId = await getCartId();
    const cart = await getClient().carts.create(
      {
        metadata: {
          checkout_source: "buy_now",
          ...(previousCartId && { previous_cart_id: previousCartId }),
        },
      },
      options,
    );
    // PALLAS-CUSTOM bugfix (2026-08-29): 新 cart 拥有自己的 token。
    // 不能复用 getCartOptions() 的旧 guestToken —— 后端 CartResolvable 用
    // `x-pallastrade-token` 对 cart 做 authorize!(:update)，旧 token 与新 cart
    // 不匹配会抛 CanCan::AccessDenied（403 "not authorized"）。同时把新 cart
    // 的 id/token 写入 cookie，供 checkout 页加载该 cart 时授权。
    const updated = await getClient().carts.items.create(
      cart.id,
      { variant_id: variantId, quantity },
      { ...options, guestToken: cart.token },
    );
    await setCartCookies(cart.id, cart.token);
    updateTag("cart");
    return { cart: updated };
  }, "Failed to start buy-now checkout");
}
