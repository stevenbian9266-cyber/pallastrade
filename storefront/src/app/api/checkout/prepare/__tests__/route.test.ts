import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/checkout/prepare/route";

const updateMock = vi.fn();
const submitMock = vi.fn();
const createTransactionMock = vi.fn();
const setCartCookiesMock = vi.fn();
const clearCartCookiesMock = vi.fn();
const setCheckoutCookiesMock = vi.fn();

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => ({
    carts: { update: updateMock, submit: submitMock },
    orders: {
      transactions: { create: createTransactionMock },
      checkout: { get: vi.fn().mockRejectedValue(new Error("no view")) },
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

function prepareRequest(
  body: unknown = {
    cart_id: "cart_1",
    checkout: {
      email: "buyer@example.com",
      shipping_method_id: "ship_1",
    },
  },
  origin = "http://shop.test",
) {
  return new NextRequest("http://shop.test/api/checkout/prepare", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      host: "shop.test",
      origin,
    },
    body: JSON.stringify(body),
  });
}

/**
 * PRD-20260915-checkout-单页两段语义 AC-001：
 * Prepare 只做 carts.update + carts.submit，**不创建支付会话/交易**，
 * 并返回 Order 权威报价供页面确认。
 */
describe("checkout prepare BFF (PRD-20260915 AC-001)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    updateMock.mockResolvedValue({
      id: "cart_1",
      token: "cart-token",
      payment_methods: [{ id: "pm_card", type: "stripe" }],
    });
    submitMock.mockResolvedValue({
      id: "or_1",
      number: "R1",
      successor_cart: { id: "cart_2", token: "successor-token" },
    });
  });

  it("submits once and returns the authoritative order quote without creating payment state (AC-001)", async () => {
    const response = await POST(prepareRequest());
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(updateMock).toHaveBeenCalledWith(
      "cart_1",
      expect.objectContaining({ email: "buyer@example.com" }),
      expect.any(Object),
    );
    expect(submitMock).toHaveBeenCalledTimes(1);
    // 关键：Prepare 绝不创建交易/会话（§0.1-2：先报价，后扣款）
    expect(createTransactionMock).not.toHaveBeenCalled();
    expect(body.order_id).toBe("or_1");
    expect(body.order.id).toBe("or_1");
    expect(body.quote).toBeNull(); // view 读取失败 → 降级 null，不改变主流程
    expect(setCheckoutCookiesMock).toHaveBeenCalledWith("or_1", "cart-token");
    expect(setCartCookiesMock).toHaveBeenCalledWith(
      "cart_2",
      "successor-token",
    );
  });

  it("rejects cross-origin prepare requests (403)", async () => {
    const response = await POST(prepareRequest(undefined, "http://evil.test"));
    const body = await response.json();

    expect(response.status).toBe(403);
    expect(body.error.code).toBe("invalid_checkout_origin");
    expect(submitMock).not.toHaveBeenCalled();
  });

  it("rejects malformed prepare requests (400)", async () => {
    const response = await POST(prepareRequest({ cart_id: "cart_1" }));

    expect(response.status).toBe(400);
    expect(submitMock).not.toHaveBeenCalled();
  });

  it("clears cart cookies when there is no successor cart", async () => {
    submitMock.mockResolvedValue({
      id: "or_2",
      number: "R2",
      successor_cart: null,
    });

    const response = await POST(prepareRequest());

    expect(response.status).toBe(200);
    expect(clearCartCookiesMock).toHaveBeenCalledTimes(1);
    expect(setCartCookiesMock).not.toHaveBeenCalled();
  });
});
