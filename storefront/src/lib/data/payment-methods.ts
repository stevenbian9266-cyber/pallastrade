"use server";

import type { PaymentMethod } from "@pallastrade/sdk";
import { getCartOptions, getClient } from "@/lib/pallastrade";
import { withFallback } from "./utils";

/**
 * PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
 * Front-facing payment methods for the combined payment page.
 */
export async function getPaymentMethods() {
  return withFallback(async () => {
    const options = await getCartOptions();
    const response = await getClient().paymentMethods.list(options);
    return response.data;
  }, [] as PaymentMethod[]);
}
