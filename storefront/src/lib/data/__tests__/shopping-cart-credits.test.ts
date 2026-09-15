import { beforeEach, describe, expect, it, vi } from "vitest";

const mockClient = {
  carts: {
    discountCodes: { apply: vi.fn(), remove: vi.fn() },
    giftCards: { apply: vi.fn(), remove: vi.fn() },
    storeCredits: { apply: vi.fn(), remove: vi.fn() },
  },
};

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => mockClient,
  getCartOptions: vi
    .fn()
    .mockResolvedValue({ guestToken: "guest-token", token: "jwt-token" }),
  getCartId: vi.fn().mockResolvedValue("cart_1"),
  getCartToken: vi.fn().mockResolvedValue("guest-token"),
  getAccessToken: vi.fn().mockResolvedValue("jwt-token"),
  setCartCookies: vi.fn(),
  clearCartCookies: vi.fn(),
  requireCartId: vi.fn().mockResolvedValue("cart_1"),
}));

vi.mock("next/cache", () => ({
  updateTag: vi.fn(),
}));

import {
  applyDiscountCode,
  applyGiftCard,
  applyStoreCredit,
  removeDiscountCode,
  removeGiftCard,
  removeStoreCredit,
} from "@/lib/data/shopping-cart";

/** 服务端 v3 错误信封形状（PallasTradeError 的鸭子类型替身）。 */
class FakeApiError extends Error {
  code: string;
  status: number;

  constructor(code: string, status = 422) {
    super(`server said ${code}`);
    this.code = code;
    this.status = status;
  }
}

const cart = { id: "cart_1", status: "active" } as never;

/**
 * 车阶段抵扣服务端动作（PRD-20260914-checkout B2）。
 * 断言点：三种抵扣在 `cart_` 上都是**意图**（零资金副作用），前端只负责
 * 记住/忘掉意图并把服务端快照透传；错误码原样上抛给 UI 做 i18n 映射。
 */
describe("shopping-cart credit actions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-004
  it("applies store credit without an amount (server means 'all available')", async () => {
    mockClient.carts.storeCredits.apply.mockResolvedValue(cart);

    const result = await applyStoreCredit("cart_1");

    expect(mockClient.carts.storeCredits.apply).toHaveBeenCalledWith(
      "cart_1",
      undefined,
      { guestToken: "guest-token", token: "jwt-token" },
    );
    expect(result).toEqual({ success: true, cart });
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-005
  it("removes store credit from the cart", async () => {
    mockClient.carts.storeCredits.remove.mockResolvedValue(cart);

    const result = await removeStoreCredit("cart_1");

    expect(mockClient.carts.storeCredits.remove).toHaveBeenCalledWith(
      "cart_1",
      {
        guestToken: "guest-token",
        token: "jwt-token",
      },
    );
    expect(result).toEqual({ success: true, cart });
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-008
  it("surfaces the server error code for store credit failures", async () => {
    mockClient.carts.storeCredits.apply.mockRejectedValue(
      new FakeApiError("store_credit_gift_card_conflict"),
    );

    const result = await applyStoreCredit("cart_1");

    expect(result).toMatchObject({
      success: false,
      code: "store_credit_gift_card_conflict",
    });
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-012
  it("omits the code for unstructured failures and keeps the message", async () => {
    mockClient.carts.storeCredits.apply.mockRejectedValue(
      new Error("boom: internal detail"),
    );

    const result = await applyStoreCredit("cart_1");

    expect(result).toEqual({ success: false, error: "boom: internal detail" });
    expect(result).not.toHaveProperty("code");
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-011
  it("applies discount codes and gift cards by code", async () => {
    mockClient.carts.discountCodes.apply.mockResolvedValue(cart);
    mockClient.carts.giftCards.apply.mockResolvedValue(cart);
    mockClient.carts.discountCodes.remove.mockResolvedValue(cart);
    mockClient.carts.giftCards.remove.mockResolvedValue(cart);

    await applyDiscountCode("cart_1", "save10");
    await applyGiftCard("cart_1", "gc-code-1");
    await removeDiscountCode("cart_1", "save10");
    await removeGiftCard("cart_1", "gc-code-1");

    expect(mockClient.carts.discountCodes.apply).toHaveBeenCalledWith(
      "cart_1",
      "save10",
      expect.anything(),
    );
    expect(mockClient.carts.giftCards.apply).toHaveBeenCalledWith(
      "cart_1",
      "gc-code-1",
      expect.anything(),
    );
    expect(mockClient.carts.discountCodes.remove).toHaveBeenCalledWith(
      "cart_1",
      "save10",
      expect.anything(),
    );
    // canonical 分支按卡码定位（车阶段一车一卡），故 id 位传 code。
    expect(mockClient.carts.giftCards.remove).toHaveBeenCalledWith(
      "cart_1",
      "gc-code-1",
      expect.anything(),
    );
  });
});
