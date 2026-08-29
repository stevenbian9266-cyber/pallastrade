"use server";

import type {
  AddressParams,
  Order,
  ShoppingCart,
} from "@pallastrade/sdk";
import { PallasTradeError } from "@pallastrade/sdk";
import { updateTag } from "next/cache";
import { redirect } from "next/navigation";
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
      explicitCartId ?? (await import("@/lib/pallastrade").then((m) => m.getCartId()));

    if (!cartId) return null;

    const cart = await getClient().carts.get(cartId, options);
    // 新 Cart 序列化器返回 ShoppingCart 形状（status/items[].selected）
    return cart as unknown as ShoppingCart;
  }, null);
}

/**
 * 更新单个商品行勾选状态。
 */
export async function updateCartItemSelection(
  cartId: string,
  itemId: string,
  selected: boolean,
): Promise<({ success: true } & { cart: ShoppingCart }) | { success: false; error: string }> {
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
): Promise<({ success: true } & { cart: ShoppingCart }) | { success: false; error: string }> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const current = await getClient().carts.get(cartId, options);
    const items = (current as unknown as ShoppingCart).items ?? [];

    for (const item of items) {
      if (item.selected !== selected) {
        await getClient().carts.items.update(cartId, item.id, { selected }, options);
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
): Promise<({ success: true } & { cart: ShoppingCart }) | { success: false; error: string }> {
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
): Promise<({ success: true } & { cart: ShoppingCart }) | { success: false; error: string }> {
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
): Promise<({ success: true } & { cart: ShoppingCart }) | { success: false; error: string }> {
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

/**
 * ★提交订单：从 Cart 创建 Order（pending）→ 前端跳转 /checkout/[orderId]。
 */
export async function submitCartOrder(cartId: string): Promise<Order> {
  const options = await getCartOptions();
  const order = await getClient().carts.submit(cartId, options);
  updateTag("cart");
  return order;
}

/**
 * 提交订单并跳转 Checkout 支付页。
 */
export async function submitCartAndGoToCheckout(cartId: string): Promise<never> {
  try {
    const order = await submitCartOrder(cartId);
    redirect(`/checkout/${order.id}`);
  } catch (error) {
    if (error instanceof PallasTradeError) {
      // 透传业务错误给表单（由客户端处理），不重定向
      throw new Error(error.message);
    }
    if (isRedirectError(error)) throw error;
    throw new Error(
      error instanceof Error ? error.message : "Failed to submit order",
    );
  }
}

// next/navigation 的 redirect 抛出 NEXT_REDIRECT——需放行
function isRedirectError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "digest" in error &&
    String((error as { digest: unknown }).digest).startsWith("NEXT_REDIRECT")
  );
}
