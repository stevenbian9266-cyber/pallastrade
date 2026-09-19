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
 * PRD-20260919-shipping-checkout-quote-preview FR-001：可选 `country` 按 zone 过滤
 * （命中不了则服务端回退全集——绝不因未建模国家而声称“不配送”）。
 */
export async function getShippingMethods(country?: string | null) {
  return withFallback(async () => {
    const options = await getCartOptions();
    return getClient().shippingMethods.list(
      country ? { country } : undefined,
      options,
    );
  }, []);
}

// ---------------------------------------------------------------------------
// 车阶段抵扣动作（PRD-20260914-checkout B2 FR-002/003/004）
//
// 三种抵扣（折扣码 / 礼品卡 / 店铺余额）在 canonical `cart_` 上都只是**意图**：
// 服务端写入 `private_metadata`（零资金副作用），真正兑现发生在提交生成 Order 时
// （`Carts::Submit` → 促销引擎 / `Checkout::AddStoreCredit`）。
// 因此这里只做两件事：记住/忘掉意图、把服务端返回的 cart 快照透传给 UI。
// 金额一律以快照为准，前端不重算（money 契约：raw 判逻辑、display 仅渲染）。
//
// 错误：`actionResult` 透传 v3 错误信封的 `code`（如 coupon_code_not_found /
// gift_card_expired / store_credit_requires_login / store_credit_gift_card_conflict），
// 供 UI 映射 i18n 文案。
// ---------------------------------------------------------------------------

/**
 * 应用优惠码到购物车（服务端规范化存储，大小写不敏感）。
 */
export async function applyDiscountCode(
  cartId: string,
  code: string,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string; code?: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.discountCodes.apply(
      cartId,
      code,
      options,
    );
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to apply discount code");
}

/**
 * 移除已应用优惠码。
 */
export async function removeDiscountCode(
  cartId: string,
  code: string,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string; code?: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.discountCodes.remove(
      cartId,
      code,
      options,
    );
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to remove discount code");
}

/**
 * 应用礼品卡到购物车（车阶段只记意图；与店铺余额互斥）。
 */
export async function applyGiftCard(
  cartId: string,
  code: string,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string; code?: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.giftCards.apply(cartId, code, options);
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to apply gift card");
}

/**
 * 移除礼品卡（车阶段一车一卡；canonical 分支按卡码定位，id 位传 code 即可）。
 */
export async function removeGiftCard(
  cartId: string,
  giftCardCode: string,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string; code?: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.giftCards.remove(
      cartId,
      giftCardCode,
      options,
    );
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to remove gift card");
}

/**
 * 应用店铺余额：**省略金额 = 用尽可用余额**（服务端 `Carts::ApplyStoreCredit` 语义，
 * 提交时按 `min(请求额, 订单应付)` 收敛）。余额是账户资产 → 需要登录（JWT），
 * 未登录时服务端返回 401 `store_credit_requires_login`。
 */
export async function applyStoreCredit(
  cartId: string,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string; code?: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.storeCredits.apply(
      cartId,
      undefined,
      options,
    );
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to apply store credit");
}

/**
 * 移除购物车上的店铺余额意图。
 */
export async function removeStoreCredit(
  cartId: string,
): Promise<
  | ({ success: true } & { cart: ShoppingCart })
  | { success: false; error: string; code?: string }
> {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cart = await getClient().carts.storeCredits.remove(cartId, options);
    updateTag("cart");
    return { cart: cart as unknown as ShoppingCart };
  }, "Failed to remove store credit");
}
