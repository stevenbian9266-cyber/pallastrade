"use server";

// P0-7 (FR-070/FR-071) → PRD-20260915-checkout B4：Cart 域 Express 入口已 **canonicalize**——
// 会话创建/完成不再经过 `carts.paymentSessions.*`（钱包确认改走 `lib/checkout/express-canonical.ts`
// 的同源 BFF：carts.update → submit → orders.transactions.create）。
// 本文件只保留**车阶段**（提交前）的准备动作：地址解析与配送费率选择。
import type { Cart } from "@pallastrade/sdk";
import {
  getCheckoutOrder,
  selectDeliveryRate,
  updateOrderAddresses,
} from "@/lib/data/checkout";
import { actionResult } from "@/lib/data/utils";

export interface ExpressCheckoutPartialAddress {
  city: string;
  postal_code: string;
  country_iso: string;
  state_name?: string;
}

export async function expressCheckoutResolveShipping(
  cartId: string,
  address: ExpressCheckoutPartialAddress,
): Promise<{ success: true; cart: Cart } | { success: false; error: string }> {
  return actionResult(async () => {
    const result = await updateOrderAddresses(cartId, {
      shipping_address: {
        ...address,
        first_name: "Express",
        last_name: "Checkout",
        address1: "TBD",
        quick_checkout: true,
      },
    });

    if (!result.success) {
      throw new Error(result.error);
    }

    const cart = await getCheckoutOrder(cartId);

    if (!cart) {
      throw new Error("Failed to fetch cart after address update");
    }

    return { cart };
  }, "Failed to resolve shipping");
}

export async function expressCheckoutSelectRates(
  cartId: string,
  selections: Array<{ fulfillmentId: string; rateId: string }>,
): Promise<{ success: true; cart: Cart } | { success: false; error: string }> {
  return actionResult(async () => {
    let cart: Cart | null = null;

    for (const { fulfillmentId, rateId } of selections) {
      const result = await selectDeliveryRate(cartId, fulfillmentId, rateId);
      if (!result.success) {
        throw new Error(result.error);
      }
      cart = result.cart;
    }

    if (!cart) {
      throw new Error("No fulfillment selections provided");
    }

    return { cart };
  }, "Failed to select shipping rates");
}

// 说明：`expressCheckoutPreparePayment` / `expressCheckoutCreateSession` /
// `expressCheckoutFinalize` 已于 B4 删除——地址/邮箱由 canonical start 的
// `checkout` 负载一并写入，会话创建/完成由 BFF（`orders.transactions` 链）承担。
