import { beforeEach, describe, expect, it, vi } from "vitest";

const mockClient = {
  carts: {
    get: vi.fn(),
    list: vi.fn(),
    paymentSessions: {
      create: vi.fn(),
      complete: vi.fn(),
    },
  },
  orders: {
    get: vi.fn(),
  },
};

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => mockClient,
  getCartToken: vi.fn().mockResolvedValue("order-token-123"),
  getCartId: vi.fn().mockResolvedValue("cart-1"),
  getAccessToken: vi.fn().mockResolvedValue(undefined),
  setCartCookies: vi.fn(),
  clearCartCookies: vi.fn(),
  getCartOptions: vi.fn().mockResolvedValue({
    guestToken: "order-token-123",
    token: undefined,
  }),
  requireCartId: vi.fn().mockResolvedValue("cart-1"),
}));

vi.mock("next/cache", () => ({
  updateTag: vi.fn(),
}));

import {
  completeCheckoutOrder,
  completeCheckoutPaymentSession,
  confirmPaymentAndCompleteCart,
  createCheckoutPaymentSession,
} from "@/lib/data/payment";

const mockSession = {
  id: "session-1",
  status: "pending",
  external_data: { client_secret: "pi_secret_123" },
};

const mockOrder = {
  id: "cart-1",
  number: "R100",
  current_step: "complete",
};

describe("payment server actions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("createCheckoutPaymentSession", () => {
    it("returns success with session", async () => {
      mockClient.carts.paymentSessions.create.mockResolvedValue(mockSession);

      const result = await createCheckoutPaymentSession("cart-1", "pm-1");

      expect(mockClient.carts.paymentSessions.create).toHaveBeenCalledWith(
        "cart-1",
        { payment_method_id: "pm-1" },
        { guestToken: "order-token-123", token: undefined },
      );
      expect(result).toEqual({ success: true, session: mockSession });
    });

    it("passes external_data when provided", async () => {
      mockClient.carts.paymentSessions.create.mockResolvedValue(mockSession);

      await createCheckoutPaymentSession("cart-1", "pm-1", {
        stripe_payment_method_id: "spm_123",
      });

      expect(mockClient.carts.paymentSessions.create).toHaveBeenCalledWith(
        "cart-1",
        {
          payment_method_id: "pm-1",
          external_data: { stripe_payment_method_id: "spm_123" },
        },
        { guestToken: "order-token-123", token: undefined },
      );
    });

    it("returns error on failure", async () => {
      mockClient.carts.paymentSessions.create.mockRejectedValue(
        new Error("Gateway unavailable"),
      );

      const result = await createCheckoutPaymentSession("cart-1", "pm-1");

      expect(result).toEqual({
        success: false,
        error: "Gateway unavailable",
      });
    });
  });

  describe("completeCheckoutPaymentSession", () => {
    it("returns success with session", async () => {
      const completedSession = { ...mockSession, status: "completed" };
      mockClient.carts.paymentSessions.complete.mockResolvedValue(
        completedSession,
      );

      const result = await completeCheckoutPaymentSession(
        "cart-1",
        "session-1",
      );

      expect(mockClient.carts.paymentSessions.complete).toHaveBeenCalledWith(
        "cart-1",
        "session-1",
        undefined,
        { guestToken: "order-token-123", token: undefined },
      );
      expect(result).toEqual({ success: true, session: completedSession });
    });

    it("returns error on failure", async () => {
      mockClient.carts.paymentSessions.complete.mockRejectedValue(
        new Error("Session expired"),
      );

      const result = await completeCheckoutPaymentSession(
        "cart-1",
        "session-1",
      );

      expect(result).toEqual({ success: false, error: "Session expired" });
    });
  });

  describe("completeCheckoutOrder", () => {
    it("returns success with the completed order (server truth)", async () => {
      mockClient.orders.get.mockResolvedValue(mockOrder);

      const result = await completeCheckoutOrder("cart-1");

      expect(mockClient.orders.get).toHaveBeenCalled();
      expect(result).toEqual({ success: true, order: mockOrder });
    });

    it("returns success with null when the order is not yet completed", async () => {
      mockClient.orders.get.mockRejectedValue(new Error("Not found"));

      const result = await completeCheckoutOrder("cart-1");

      expect(result).toEqual({ success: true, order: null });
    });

    it("no longer references the dead carts.complete endpoint", () => {
      expect(mockClient.carts).not.toHaveProperty("complete");
    });
  });

  describe("confirmPaymentAndCompleteCart", () => {
    it("passes cartId to getCart for explicit lookup", async () => {
      mockClient.carts.get.mockResolvedValue({
        id: "cart-1",
        current_step: "complete",
      });

      await confirmPaymentAndCompleteCart("cart-1", "session-1");

      expect(mockClient.carts.get).toHaveBeenCalledWith("cart-1", {
        guestToken: "order-token-123",
        token: undefined,
      });
    });

    it("succeeds when cart is already complete", async () => {
      mockClient.carts.get.mockResolvedValue({
        id: "cart-1",
        current_step: "complete",
      });

      const result = await confirmPaymentAndCompleteCart("cart-1", "session-1");

      expect(result).toEqual({
        success: true,
        order: { id: "cart-1", current_step: "complete" },
      });
      expect(mockClient.carts.paymentSessions.complete).not.toHaveBeenCalled();
      expect(mockClient.orders.get).not.toHaveBeenCalled();
    });

    it("completes payment session then reads order server truth", async () => {
      mockClient.carts.get.mockResolvedValue({
        id: "cart-1",
        current_step: "payment",
      });
      mockClient.carts.paymentSessions.complete.mockResolvedValue({
        id: "session-1",
        status: "completed",
      });
      mockClient.orders.get.mockResolvedValue(mockOrder);

      const result = await confirmPaymentAndCompleteCart("cart-1", "session-1");

      expect(mockClient.carts.paymentSessions.complete).toHaveBeenCalled();
      expect(mockClient.orders.get).toHaveBeenCalled();
      expect(result).toEqual({ success: true, order: mockOrder });
    });

    it("returns success with null order when order fetch finds nothing yet", async () => {
      mockClient.carts.get.mockResolvedValue({
        id: "cart-1",
        current_step: "payment",
      });
      mockClient.carts.paymentSessions.complete.mockResolvedValue({
        id: "session-1",
        status: "completed",
      });
      mockClient.orders.get.mockRejectedValue(new Error("Not found"));

      const result = await confirmPaymentAndCompleteCart("cart-1", "session-1");

      expect(result).toEqual({ success: true, order: null });
    });

    it("returns error when payment session fails", async () => {
      mockClient.carts.get.mockResolvedValue({
        id: "cart-1",
        current_step: "payment",
      });
      mockClient.carts.paymentSessions.complete.mockResolvedValue({
        id: "session-1",
        status: "failed",
      });

      const result = await confirmPaymentAndCompleteCart("cart-1", "session-1");

      expect(result).toEqual({
        success: false,
        error: "Payment was not successful. Please try again.",
      });
      expect(mockClient.orders.get).not.toHaveBeenCalled();
    });

    it("skips session completion when no session ID provided", async () => {
      mockClient.carts.get.mockResolvedValue({
        id: "cart-1",
        current_step: "payment",
      });
      mockClient.orders.get.mockResolvedValue(mockOrder);

      const result = await confirmPaymentAndCompleteCart("cart-1");

      expect(mockClient.carts.paymentSessions.complete).not.toHaveBeenCalled();
      expect(mockClient.orders.get).toHaveBeenCalled();
      expect(result).toEqual({ success: true, order: mockOrder });
    });

    it("returns success when cart is not found (already completed by webhook)", async () => {
      mockClient.carts.get.mockRejectedValue(new Error("Not found"));
      mockClient.orders.get.mockRejectedValue(new Error("Not found"));

      const result = await confirmPaymentAndCompleteCart("cart-1", "session-1");

      expect(mockClient.orders.get).toHaveBeenCalled();
      expect(result).toEqual({ success: true, order: null });
    });

    it("returns success with null when getCart throws (order state unknown)", async () => {
      mockClient.carts.get.mockRejectedValue("unexpected");
      mockClient.orders.get.mockRejectedValue(new Error("Not found"));

      const result = await confirmPaymentAndCompleteCart("cart-1");

      // getCart() returns null on error (clears stale cookies), so the flow reads
      // order server truth (null → pending/unknown; payment-result decides final state)
      expect(result).toEqual({ success: true, order: null });
    });
  });
});
