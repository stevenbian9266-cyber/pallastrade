import { beforeEach, describe, expect, it, vi } from "vitest";

const mockClient = {
  carts: {
    get: vi.fn(),
    list: vi.fn(),
    update: vi.fn(),
    complete: vi.fn(),
    fulfillments: { update: vi.fn() },
    discountCodes: { apply: vi.fn(), remove: vi.fn() },
    giftCards: { apply: vi.fn(), remove: vi.fn() },
  },
  orders: { get: vi.fn() },
};

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => mockClient,
  getCartToken: vi.fn().mockResolvedValue("order-token-123"),
  getCartId: vi.fn().mockResolvedValue("order-1"),
  getAccessToken: vi.fn().mockResolvedValue(undefined),
  setCartCookies: vi.fn(),
  clearCartCookies: vi.fn(),
  getCartOptions: vi.fn().mockResolvedValue({
    guestToken: "order-token-123",
    token: undefined,
  }),
  requireCartId: vi.fn().mockResolvedValue("order-1"),
  withAuthRefresh: vi.fn(
    async (fn: (options: { token: string }) => Promise<unknown>) => {
      return fn({ token: "jwt-token" });
    },
  ),
}));

vi.mock("@pallastrade/sdk", () => ({
  PallasTradeError: class PallasTradeError extends Error {
    code: string;
    status: number;
    constructor(
      response: { error: { code: string; message: string } },
      status: number,
    ) {
      super(response.error.message);
      this.code = response.error.code;
      this.status = status;
    }
  },
}));

vi.mock("next/cache", () => ({
  updateTag: vi.fn(),
}));

import {
  getCheckoutOrder,
  selectDeliveryRate,
  updateCartMarket,
  updateOrderAddresses,
} from "@/lib/data/checkout";

const mockOrder = {
  id: "order-1",
  status: "active",
  number: "R100",
  current_step: "address",
};

describe("checkout server actions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("getCheckoutOrder", () => {
    it("returns cart when still in checkout", async () => {
      mockClient.carts.get.mockResolvedValue(mockOrder);

      const result = await getCheckoutOrder("order-1");

      expect(mockClient.carts.get).toHaveBeenCalled();
      expect(result).toBe(mockOrder);
    });

    it("falls back to getOrder when cart is null (completed)", async () => {
      const completedOrder = { ...mockOrder, current_step: "complete" };
      mockClient.carts.get.mockRejectedValue(new Error("Not found"));
      mockClient.orders.get.mockResolvedValue(completedOrder);

      const result = await getCheckoutOrder("order-1");

      expect(mockClient.orders.get).toHaveBeenCalled();
      expect(result).toBe(completedOrder);
    });

    it("returns null when both cart and order fail", async () => {
      mockClient.carts.get.mockRejectedValue(new Error("Not found"));
      mockClient.orders.get.mockRejectedValue(new Error("Not found"));

      const result = await getCheckoutOrder("bad-id");

      expect(result).toBeNull();
    });
  });

  describe("updateOrderAddresses", () => {
    it("returns success with order", async () => {
      mockClient.carts.update.mockResolvedValue(mockOrder);
      const addresses = { email: "test@example.com" };

      const result = await updateOrderAddresses("order-1", addresses);

      expect(mockClient.carts.update).toHaveBeenCalledWith(
        "order-1",
        addresses,
        { guestToken: "order-token-123", token: undefined },
      );
      expect(result).toEqual({ success: true, cart: mockOrder });
    });

    it("returns error on failure", async () => {
      mockClient.carts.update.mockRejectedValue(new Error("Invalid address"));

      const result = await updateOrderAddresses("order-1", {});

      expect(result).toEqual({
        success: false,
        error: "Invalid address",
      });
    });

    it("returns fallback message for non-Error throws", async () => {
      mockClient.carts.update.mockRejectedValue("unexpected");

      const result = await updateOrderAddresses("order-1", {});

      expect(result).toEqual({
        success: false,
        error: "Failed to update addresses",
      });
    });
  });

  describe("updateCartMarket", () => {
    it("returns success with updated order", async () => {
      const updatedOrder = { ...mockOrder, currency: "EUR", locale: "de" };
      mockClient.carts.update.mockResolvedValue(updatedOrder);

      const result = await updateCartMarket("order-1", {
        currency: "EUR",
        locale: "de",
      });

      expect(mockClient.carts.update).toHaveBeenCalledWith(
        "order-1",
        { currency: "EUR", locale: "de" },
        { guestToken: "order-token-123", token: undefined },
      );
      expect(result).toEqual({ success: true, cart: updatedOrder });
    });

    it("returns error on failure", async () => {
      mockClient.carts.update.mockRejectedValue(
        new Error("Currency not supported"),
      );

      const result = await updateCartMarket("order-1", {
        currency: "XYZ",
        locale: "en",
      });

      expect(result).toEqual({
        success: false,
        error: "Currency not supported",
      });
    });

    it("returns fallback message for non-Error throws", async () => {
      mockClient.carts.update.mockRejectedValue("unexpected");

      const result = await updateCartMarket("order-1", {
        currency: "EUR",
        locale: "de",
      });

      expect(result).toEqual({
        success: false,
        error: "Failed to update order market",
      });
    });
  });

  describe("selectDeliveryRate", () => {
    it("returns success", async () => {
      mockClient.carts.fulfillments.update.mockResolvedValue(undefined);

      const result = await selectDeliveryRate("order-1", "ship-1", "rate-1");

      expect(mockClient.carts.fulfillments.update).toHaveBeenCalledWith(
        "order-1",
        "ship-1",
        { selected_delivery_rate_id: "rate-1" },
        { guestToken: "order-token-123", token: undefined },
      );
      expect(result).toEqual({ success: true });
    });

    it("returns error on failure", async () => {
      mockClient.carts.fulfillments.update.mockRejectedValue(
        new Error("Rate not available"),
      );

      const result = await selectDeliveryRate("order-1", "ship-1", "rate-1");

      expect(result).toEqual({
        success: false,
        error: "Rate not available",
      });
    });
  });
});
