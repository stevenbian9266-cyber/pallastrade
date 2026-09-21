import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

// PRD-20260921-checkout-place-order-正名与显式化 AC-005 / AC-006 / AC-007：
// Place Order 是 BFF 的「第一段：建单」；旧路径 prepare 必须**行为等价**且
// **实现只存在一份**（不得复制业务逻辑）。

const sameOriginMock = vi.hoisted(() => vi.fn(() => true));

const cartsUpdate = vi.hoisted(() => vi.fn());
const cartsSubmit = vi.hoisted(() => vi.fn());

vi.mock("@/lib/checkout/server", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/lib/checkout/server")>();
  return {
    ...actual,
    sameOrigin: sameOriginMock,
    readQuote: async () => ({ quote_version: "v1" }),
  };
});

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => ({ carts: { update: cartsUpdate, submit: cartsSubmit } }),
  getCartOptions: async () => ({}),
  setCheckoutCookies: vi.fn(async () => {}),
  setCartCookies: vi.fn(async () => {}),
  clearCartCookies: vi.fn(async () => {}),
}));

import { POST as placeOrderPOST } from "../route";
import { POST as preparePOST } from "../../prepare/route";

function makeRequest(body: unknown): NextRequest {
  return new NextRequest("http://localhost/api/checkout/place-order", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

const VALID_BODY = {
  cart_id: "cart_1",
  checkout: { email: "ada@example.com" },
};

describe("/api/checkout/place-order", () => {
  beforeEach(() => {
    sameOriginMock.mockReturnValue(true);
    cartsUpdate.mockReset();
    cartsSubmit.mockReset();
  });

  // PRD-20260921-checkout-place-order-正名与显式化 AC-005
  it("keeps the legacy prepare path as a thin alias of the same handler (implementation exists once)", async () => {
    // 实现只能存在一份：别名必须是**同一个函数引用**，而不是复制的实现。
    expect(preparePOST).toBe(placeOrderPOST);
  });

  // PRD-20260921-checkout-place-order-正名与显式化 AC-001
  it("creates the order and returns the authoritative quote shape", async () => {
    cartsUpdate.mockResolvedValue({ token: "cart_tok" });
    cartsSubmit.mockResolvedValue({
      id: "or_123",
      number: "R123",
      successor_cart: null,
    });

    const response = await placeOrderPOST(makeRequest(VALID_BODY));
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.order_id).toBe("or_123");
    expect(json.order).toMatchObject({ id: "or_123", number: "R123" });
    expect(json.quote).toBeTruthy();
    expect(cartsUpdate).toHaveBeenCalledTimes(1);
    expect(cartsSubmit).toHaveBeenCalledTimes(1);
  });

  // PRD-20260921-checkout-place-order-正名与显式化 AC-006
  it("keeps the same-origin guard (403) — the alias must not bypass it", async () => {
    sameOriginMock.mockReturnValue(false);

    const response = await placeOrderPOST(makeRequest(VALID_BODY));
    const json = await response.json();

    expect(response.status).toBe(403);
    expect(json.error.code).toBe("invalid_checkout_origin");
    expect(cartsSubmit).not.toHaveBeenCalled();
  });

  // PRD-20260921-checkout-place-order-正名与显式化 AC-007
  it("returns 400 (not 500) for a malformed body", async () => {
    const response = await placeOrderPOST(makeRequest({ cart_id: "cart_1" }));
    const json = await response.json();

    expect(response.status).toBe(400);
    expect(json.error.code).toBe("invalid_request");
    expect(cartsSubmit).not.toHaveBeenCalled();
  });

  // PRD-20260921-checkout-place-order-正名与显式化 AC-005（行为等价）
  it("behaves identically when called through the legacy path", async () => {
    const respond = () => {
      cartsUpdate.mockResolvedValue({ token: "cart_tok" });
      cartsSubmit.mockResolvedValue({
        id: "or_123",
        number: "R123",
        successor_cart: null,
      });
    };

    respond();
    const viaNew = await placeOrderPOST(makeRequest(VALID_BODY));

    respond();
    const viaLegacy = await preparePOST(makeRequest(VALID_BODY));

    expect(viaLegacy.status).toBe(viaNew.status);
    expect(await viaLegacy.json()).toEqual(await viaNew.json());
  });
});
