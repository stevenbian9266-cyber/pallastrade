import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PATCH, POST } from "@/app/api/checkout/start/route";

const updateMock = vi.fn();
const submitMock = vi.fn();
const createSessionMock = vi.fn();
const completeSessionMock = vi.fn();
const setCartCookiesMock = vi.fn();
const clearCartCookiesMock = vi.fn();
const setCheckoutCookiesMock = vi.fn();

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => ({
    carts: { update: updateMock, submit: submitMock },
    orders: {
      paymentSessions: {
        create: createSessionMock,
        complete: completeSessionMock,
      },
    },
  }),
  getCartOptions: vi
    .fn()
    .mockResolvedValue({ headers: { "X-Cart-Token": "token" } }),
  getCheckoutOptions: vi
    .fn()
    .mockResolvedValue({ headers: { "X-Cart-Token": "checkout-token" } }),
  setCartCookies: (...args: unknown[]) => setCartCookiesMock(...args),
  clearCartCookies: () => clearCartCookiesMock(),
  setCheckoutCookies: (...args: unknown[]) => setCheckoutCookiesMock(...args),
}));

function checkoutRequest(origin = "http://shop.test") {
  return new NextRequest("http://shop.test/api/checkout/start", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      host: "shop.test",
      origin,
    },
    body: JSON.stringify({
      cart_id: "cart_1",
      payment_method_id: "pm_card",
      payment_mode: "payment_intent",
      checkout: {
        email: "buyer@example.com",
        shipping_method_id: "ship_1",
      },
    }),
  });
}

describe("checkout start BFF (PRD-20260830-checkout AC-002/003/007)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    updateMock.mockResolvedValue({
      id: "cart_1",
      token: "cart-token",
      payment_methods: [
        {
          id: "pm_card",
          type: "stripe",
          session_required: true,
        },
      ],
    });
    submitMock.mockResolvedValue({
      id: "or_1",
      number: "R1",
      successor_cart: { id: "cart_2", token: "successor-token" },
    });
    createSessionMock.mockResolvedValue({
      id: "ps_1",
      external_data: { client_secret: "pi_secret" },
    });
    completeSessionMock.mockResolvedValue({ id: "ps_1", status: "completed" });
  });

  it("submits once, starts the Order session, and activates the successor cart", async () => {
    const response = await POST(checkoutRequest());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(updateMock).toHaveBeenCalledWith(
      "cart_1",
      expect.objectContaining({ email: "buyer@example.com" }),
      expect.any(Object),
    );
    expect(submitMock).toHaveBeenCalledTimes(1);
    expect(createSessionMock).toHaveBeenCalledWith(
      "or_1",
      {
        payment_method_id: "pm_card",
        external_data: { mode: "payment_intent" },
      },
      expect.any(Object),
    );
    expect(setCheckoutCookiesMock).toHaveBeenCalledWith("or_1", "cart-token");
    expect(setCartCookiesMock).toHaveBeenCalledWith(
      "cart_2",
      "successor-token",
    );
    expect(body).toMatchObject({
      order: { id: "or_1" },
      session: { id: "ps_1" },
    });
    expect(body.order).not.toHaveProperty("successor_cart");
  });

  it("returns the created order id when session startup fails", async () => {
    createSessionMock.mockRejectedValue(new Error("provider unavailable"));

    const response = await POST(checkoutRequest());

    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({ order_id: "or_1" });
    expect(setCheckoutCookiesMock).toHaveBeenCalledWith("or_1", "cart-token");
  });

  it("rejects a cross-origin checkout command before touching the cart", async () => {
    const response = await POST(checkoutRequest("http://attacker.test"));

    expect(response.status).toBe(403);
    expect(updateMock).not.toHaveBeenCalled();
    expect(submitMock).not.toHaveBeenCalled();
  });

  it("completes an existing Order session through the checkout token", async () => {
    const request = new NextRequest("http://shop.test/api/checkout/start", {
      method: "PATCH",
      headers: {
        "content-type": "application/json",
        host: "shop.test",
        origin: "http://shop.test",
      },
      body: JSON.stringify({ order_id: "or_1", session_id: "ps_1" }),
    });

    const response = await PATCH(request);

    expect(response.status).toBe(200);
    expect(completeSessionMock).toHaveBeenCalledWith(
      "or_1",
      "ps_1",
      undefined,
      expect.any(Object),
    );
  });
});
