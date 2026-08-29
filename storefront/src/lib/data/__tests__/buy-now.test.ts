import { beforeEach, describe, expect, it, vi } from "vitest";

const mockClient = {
  carts: {
    create: vi.fn(),
    items: {
      create: vi.fn(),
    },
  },
};

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => mockClient,
  getCartOptions: vi.fn().mockResolvedValue({
    guestToken: "old-cart-token",
    token: undefined,
  }),
  setCartCookies: vi.fn(),
}));

vi.mock("next/cache", () => ({
  updateTag: vi.fn(),
}));

import { createBuyNowCart } from "@/lib/data/buy-now";
import { setCartCookies } from "@/lib/pallastrade";

// Minimal cart fixture
const newCart = {
  id: "cart_buynow1",
  number: "R777777",
  state: "cart",
  token: "new-cart-token-456",
  items: [],
  total: "0.00",
};

describe("createBuyNowCart", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.carts.create.mockResolvedValue(newCart);
    mockClient.carts.items.create.mockResolvedValue({
      ...newCart,
      items: [{ id: "line_1", variant_id: "variant_1", quantity: 1 }],
    });
  });

  it("uses the NEW cart token (not the stale guest token) when adding the item", async () => {
    await createBuyNowCart("variant_1", 1);

    expect(mockClient.carts.create).toHaveBeenCalledWith(
      {},
      { guestToken: "old-cart-token", token: undefined },
    );
    // The item must be added with the new cart's own token — reusing the old
    // guest token makes the backend's authorize!(:update, cart, cart_token)
    // fail with CanCan::AccessDenied (403 "not authorized").
    expect(mockClient.carts.items.create).toHaveBeenCalledWith(
      "cart_buynow1",
      { variant_id: "variant_1", quantity: 1 },
      { guestToken: "new-cart-token-456", token: undefined },
    );
  });

  it("persists the new cart id/token to cookies so the checkout page can authorize", async () => {
    await createBuyNowCart("variant_1", 1);

    expect(setCartCookies).toHaveBeenCalledWith(
      "cart_buynow1",
      "new-cart-token-456",
    );
  });

  it("returns the updated cart", async () => {
    const result = await createBuyNowCart("variant_1", 2);

    expect(result).toEqual({
      success: true,
      cart: {
        ...newCart,
        items: [{ id: "line_1", variant_id: "variant_1", quantity: 1 }],
      },
    });
  });

  it("returns { error } when the cart creation fails", async () => {
    mockClient.carts.create.mockRejectedValueOnce(
      Object.assign(new Error("upstream"), { message: "Something broke" }),
    );

    const result = await createBuyNowCart("variant_1", 1);

    expect("error" in result).toBe(true);
    expect(mockClient.carts.items.create).not.toHaveBeenCalled();
  });
});
