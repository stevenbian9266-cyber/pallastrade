"use server";

import type { AddressParams, Cart } from "@pallastrade/sdk";
import { updateTag } from "next/cache";
import { getCartOptions, getClient, requireCartId } from "@/lib/pallastrade";
import { getCart } from "./cart";
import { getOrder } from "./orders";
import { actionResult, withFallback } from "./utils";

export async function getCheckoutOrder(cartId: string): Promise<Cart | null> {
  // Try active cart first (order may still be in checkout)
  const cart = await getCart();
  if (cart && cart.id === cartId) return cart;

  // Cart completed — fetch as completed order.
  return withFallback(
    async () => (await getOrder(cartId)) as unknown as Cart,
    null,
  );
}

export async function getCompletedOrder(cartId: string): Promise<Cart | null> {
  // Fetch order directly — used by the order-placed page.
  // Does not call getCart() first because getCart() auto-clears
  // the cart token cookie on failure, which breaks getOrder()
  // for guest users.
  return withFallback(
    async () => (await getOrder(cartId)) as unknown as Cart,
    null,
  );
}

export async function updateOrderAddresses(
  cartId: string,
  addresses: {
    shipping_address?: AddressParams;
    billing_address?: AddressParams;
    shipping_address_id?: string;
    billing_address_id?: string;
    use_shipping?: boolean;
    email?: string;
  },
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const id = await requireCartId();
    const cart = await getClient().carts.update(id, addresses, options);
    updateTag("checkout");
    return { cart };
  }, "Failed to update addresses");
}

export async function updateCartMarket(
  cartId: string,
  params: { currency: string; locale: string },
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const id = await requireCartId();
    const cart = await getClient().carts.update(id, params, options);
    updateTag("checkout");
    return { cart };
  }, "Failed to update order market");
}

export async function selectDeliveryRate(
  cartId: string,
  fulfillmentId: string,
  deliveryRateId: string,
) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const id = await requireCartId();
    const cart = await getClient().carts.fulfillments.update(
      id,
      fulfillmentId,
      { selected_delivery_rate_id: deliveryRateId },
      options,
    );
    updateTag("checkout");
    return { cart };
  }, "Failed to select delivery rate");
}
