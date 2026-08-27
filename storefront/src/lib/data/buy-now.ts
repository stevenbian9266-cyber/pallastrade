"use server";

import { updateTag } from "next/cache";
import { getCartOptions, getClient } from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * Buy Now（P5, 2026-08-27）：创建含当前商品的独立 cart 并直接进入确认页，
 * 不污染既有购物车。
 */
export async function createBuyNowCart(variantId: string, quantity = 1) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.create({}, options);
    const updated = await getClient().carts.items.create(
      cart.id,
      { variant_id: variantId, quantity },
      options,
    );
    updateTag("cart");
    return { cart: updated };
  }, "Failed to start buy-now checkout");
}
