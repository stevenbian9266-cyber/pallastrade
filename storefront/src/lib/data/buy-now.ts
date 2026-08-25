"use server";

// PALLAS-CUSTOM: Buy Now 快捷下单（PRD-20260824 FR-011）
// 商品详情页「Buy Now」→ 创建仅含当前商品（+数量）的快捷购物车并切换 cookie，
// 不污染用户原购物车（进入前备份，完成后 restorePreviousCart 恢复）。
// 未登录用户在客户端先跳转登录并回跳确认页（FR-001）。

import { updateTag } from "next/cache";
import {
  backupCartCookies,
  getAccessToken,
  getClient,
  getLocaleOptions,
  restoreCartCookies,
  setCartCookies,
} from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * 创建 Buy Now 快捷购物车（仅含当前商品+数量）并切换当前购物车 cookie。
 * 原购物车 cookie 先备份到 *_prev 专用 cookie，完成后可恢复。
 * @returns { cartId } 快捷购物车 id，客户端据此跳转公用确认页
 */
export async function buyNow(variantId: string, quantity: number) {
  return actionResult(async () => {
    if (!variantId) {
      throw new Error("No variant selected");
    }
    // 备份原购物车（Buy Now 结算完成后恢复，FR-011 不污染购物车）
    await backupCartCookies();

    const token = await getAccessToken();
    const localeOptions = await getLocaleOptions();
    const cart = await getClient().carts.create(
      { items: [{ variant_id: variantId, quantity: quantity || 1 }] },
      { ...localeOptions, ...(token ? { token } : undefined) },
    );

    await setCartCookies(cart.id, cart.token);
    updateTag("cart");
    return { cartId: cart.id };
  }, "Failed to start Buy Now checkout");
}

/**
 * 恢复 Buy Now 之前备份的原购物车 cookie（快捷订单结算完成后调用，
 * 让用户回到原购物车内容，符合 FR-011「不污染购物车」）。
 */
export async function restorePreviousCart() {
  return actionResult(async () => {
    await restoreCartCookies();
    updateTag("cart");
    return {};
  }, "Failed to restore cart");
}
