import { beforeEach, describe, expect, it, vi } from "vitest";

const mockClient = {
  carts: {
    create: vi.fn(),
    get: vi.fn(),
  },
};

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => mockClient,
  getAccessToken: vi.fn().mockResolvedValue(undefined),
  getLocaleOptions: vi.fn().mockResolvedValue({ locale: "en", country: "us" }),
  setCartCookies: vi.fn(),
  backupCartCookies: vi.fn(),
  restoreCartCookies: vi.fn(),
  clearPrevCartCookies: vi.fn(),
}));

vi.mock("next/cache", () => ({
  updateTag: vi.fn(),
}));

// # PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 AC-011
// Buy Now：创建仅含当前商品的快捷购物车（不污染原购物车，先备份），
// 完成后 restorePreviousCart 恢复原购物车
import { buyNow, restorePreviousCart } from "@/lib/data/buy-now";

describe("buy-now server actions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockClient.carts.create.mockResolvedValue({
      id: "cart-bn-1",
      token: "bn-token",
    });
  });

  it("AC-011: buyNow 创建仅含指定商品+数量的快捷购物车并切换 cookie", async () => {
    const result = await buyNow("var_123", 2);

    expect(result.success).toBe(true);
    expect(mockClient.carts.create).toHaveBeenCalledWith(
      { items: [{ variant_id: "var_123", quantity: 2 }] },
      expect.objectContaining({ locale: "en", country: "us" }),
    );
    expect(result).toMatchObject({ cartId: "cart-bn-1" });
  });

  it("AC-011: 进入前备份原购物车（不污染购物车）", async () => {
    const { backupCartCookies } = await import("@/lib/pallastrade");

    await buyNow("var_123", 1);

    expect(backupCartCookies).toHaveBeenCalled();
  });

  it("AC-011: 默认数量为 1", async () => {
    await buyNow("var_123", 0);

    expect(mockClient.carts.create).toHaveBeenCalledWith(
      { items: [{ variant_id: "var_123", quantity: 1 }] },
      expect.anything(),
    );
  });

  it("AC-011: 无 variant 时返回明确错误", async () => {
    const result = await buyNow("", 1);

    expect(result.success).toBe(false);
    expect(mockClient.carts.create).not.toHaveBeenCalled();
  });

  it("AC-011: restorePreviousCart 恢复原购物车 cookie", async () => {
    const { restoreCartCookies } = await import("@/lib/pallastrade");

    const result = await restorePreviousCart();

    expect(result.success).toBe(true);
    expect(restoreCartCookies).toHaveBeenCalled();
  });
});
