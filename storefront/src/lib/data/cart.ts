"use server";

import type { Cart, CreateCartParams, ShoppingCart } from "@pallastrade/sdk";
import { updateTag } from "next/cache";
import {
  clearCartCookies,
  getAccessToken,
  getCartId,
  getCartOptions,
  getCartToken,
  getClient,
  getLocaleOptions,
  requireCartId,
  setCartCookies,
} from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * Get the current cart. Returns null if no cart exists.
 */
export async function getCart(explicitCartId?: string): Promise<Cart | null> {
  const guestToken = await getCartToken();
  const token = await getAccessToken();
  const cartId = explicitCartId ?? (await getCartId());

  if (!cartId && !token) return null;

  try {
    if (cartId) {
      const cart = await getClient().carts.get(cartId, { guestToken, token });
      if (!explicitCartId && !isActiveCart(cart)) {
        return null;
      }
      return cart;
    }

    // Authenticated user without stored cart ID — find their most recent cart
    if (token) {
      const response = await getClient().carts.list({ token });
      if (response.data.length > 0) {
        const cart = response.data[0];
        if (!isActiveCart(cart)) return null;
        await setCartCookies(cart.id, cart.token);
        return cart;
      }
    }

    return null;
  } catch {
    // Cart not found (e.g., order was completed) — clear stale cookies.
    // Wrapped in try/catch because clearCartCookies sets cookies, which
    // is not allowed in Server Components (only in Server Actions).
    if (!explicitCartId) {
      await clearStaleCartCookies();
    }
    return null;
  }
}

function isActiveCart(cart: Cart): boolean {
  return (cart as unknown as ShoppingCart).status === "active";
}

async function clearStaleCartCookies(): Promise<void> {
  try {
    await clearCartCookies();
  } catch {
    // Cookie writes are unavailable while rendering Server Components.
  }
}

/**
 * Get existing cart or create a new one.
 */
export async function getOrCreateCart(
  params?: CreateCartParams,
): Promise<Cart> {
  const existing = await getCart();
  if (existing) return existing;

  const token = await getAccessToken();
  const localeOptions = await getLocaleOptions();
  const cartParams =
    params && Object.keys(params).length > 0 ? params : undefined;
  const cart = await getClient().carts.create(cartParams, {
    ...localeOptions,
    ...(token ? { token } : undefined),
  });

  await setCartCookies(cart.id, cart.token);

  updateTag("cart");
  return cart;
}

export async function clearCart() {
  return actionResult(async () => {
    await clearCartCookies();
    updateTag("cart");
    return {};
  }, "Failed to clear cart");
}

export async function addToCart(variantId: string, quantity: number) {
  return actionResult(async () => {
    const cart = await getOrCreateCart();
    const guestToken = await getCartToken();
    const token = await getAccessToken();

    const updatedCart = await getClient().carts.items.create(
      cart.id,
      { variant_id: variantId, quantity },
      { guestToken, token },
    );

    updateTag("cart");
    return { cart: updatedCart };
  }, "Failed to add item to cart");
}

export async function updateCartItem(lineItemId: string, quantity: number) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cartId = await requireCartId();

    const cart = await getClient().carts.items.update(
      cartId,
      lineItemId,
      { quantity },
      options,
    );

    updateTag("cart");
    return { cart };
  }, "Failed to update cart item");
}

export async function removeCartItem(lineItemId: string) {
  return actionResult(async () => {
    const options = await getCartOptions();
    const cartId = await requireCartId();

    const cart = await getClient().carts.items.delete(
      cartId,
      lineItemId,
      options,
    );

    updateTag("cart");
    return { cart };
  }, "Failed to remove cart item");
}

export async function associateCartWithUser() {
  return actionResult(async () => {
    const guestToken = await getCartToken();
    const token = await getAccessToken();
    const cartId = await getCartId();
    if (!cartId || !token) return {};

    try {
      await getClient().carts.associate(cartId, { guestToken, token });
      updateTag("cart");
    } catch {
      // Cart might already belong to another user — clear it
      await clearCartCookies();
      updateTag("cart");
    }
    return {};
  }, "Failed to associate cart");
}
