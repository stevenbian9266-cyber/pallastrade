"use server";

import type { AddressParams, ShoppingCart } from "@pallastrade/sdk";
import { updateTag } from "next/cache";
import { getCartOptions, getClient } from "@/lib/pallastrade";
import { actionResult, withFallback } from "./utils";

/**
 * 订单流程标准电商改造 P1（2026-08-30）：新购物车（pallastrade_carts）数据层。
 * 与 legacy `lib/data/cart.ts`（Order 同表）分离——本模块操作新 Cart 实体。
 */

/**
 * 获取新购物车（pallastrade_carts 形状，含 items.selected）。
 */
export async function getShoppingCart(
  explicitCartId?: string,
): Promise<ShoppingCart | null> {
  return withFallback(async () => {
    const options = await getCartOptions();
    const cartId =
      explicitCartId ??
      (await import("@/lib/pallastrade").then((m) => m.getCartId()));

    if (!cartId) return null;

    const cart = await getClient().carts.get(cartId, options);
    const shoppingCart = cart as unknown as ShoppingCart;
    if (!explicitCartId && shoppingCart.status !== "active") return null;

    // 新 Cart 序列化器返回 ShoppingCart 形状（status/items[].selected）
    return shoppingCart;
  }, null);
}

/**
 * 更新单个商品行勾选状态。
 */
export async function updateCartItemSelection(
  cartId: string,
  itemId: string,
  selected: boolean,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.items.update(
      cartId,
      itemId,
      { selected },
      options,
    );
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to update cart item selection");
}

/**
 * 全选/全不选。
 */
export async function setAllCartItemsSelected(
  cartId: string,
  selected: boolean,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const current = await getClient().carts.get(cartId, options);
    const items = (current as unknown as ShoppingCart).items ?? [];

    for (const item of items) {
      if (item.selected !== selected) {
        await getClient().carts.items.update(
          cartId,
          item.id,
          { selected },
          options,
        );
      }
    }
    updateTag("cart");
    const updated = await getClient().carts.get(cartId, options);
    return { cart: updated as unknown as ShoppingCart };
  }, "Failed to update cart selection");
}

/**
 * 更新购物车商品数量（购物车页）。
 */
export async function updateCartItemQuantity(
  cartId: string,
  itemId: string,
  quantity: number,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.items.update(
      cartId,
      itemId,
      { quantity },
      options,
    );
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to update cart item quantity");
}

/**
 * 删除购物车商品行（购物车页）。
 */
export async function removeCartItem(
  cartId: string,
  itemId: string,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.items.delete(cartId, itemId, options);
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to remove cart item");
}

/**
 * 订单确认页：保存 email / 收件地址 / 配送方式。
 */
export async function updateShoppingCartDetails(
  cartId: string,
  params: {
    email?: string;
    shipping_address?: AddressParams;
    shipping_method_id?: string;
  },
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.update(cartId, params, options);
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to save checkout details");
}

/**
 * 列出订单确认页可选配送方式（前端展示，含费率标签）。
 */
export async function getShippingMethods() {
  return withFallback(async () => {
    const options = await getCartOptions();
    return getClient().shippingMethods.list(options);
  }, []);
}
