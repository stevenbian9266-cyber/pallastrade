import { describe, expect, it } from "vitest";
import { recoveryRouteForConvertedCart } from "@/lib/checkout/recovery";

/**
 * PRD-20260919-checkout-express-always-visible-and-pi-params AC-009（FR-006）：
 * 转换后购物车页的恢复目标 —— 有待支付订单 → 订单支付页；否则 → 购物车页。
 */
describe("recoveryRouteForConvertedCart (AC-009)", () => {
  it("routes to the order payment page when a pending order is remembered", () => {
    expect(
      recoveryRouteForConvertedCart({
        country: "us",
        locale: "en",
        pendingOrderId: "or_X35bb5HTmV",
      }),
    ).toBe("/us/en/checkout/or_X35bb5HTmV");
  });

  it("keeps the country/locale prefix of the request", () => {
    expect(
      recoveryRouteForConvertedCart({
        country: "de",
        locale: "de",
        pendingOrderId: "or_1",
      }),
    ).toBe("/de/de/checkout/or_1");
  });

  it("falls back to the cart page without a pending order", () => {
    expect(
      recoveryRouteForConvertedCart({
        country: "us",
        locale: "en",
        pendingOrderId: null,
      }),
    ).toBe("/us/en/cart");
  });

  // 边界：非订单前缀（cookie 被篡改 / 旧格式）→ 不制造奇怪跳转，回落购物车页。
  it("ignores cookie values that are not order ids", () => {
    expect(
      recoveryRouteForConvertedCart({
        country: "us",
        locale: "en",
        pendingOrderId: "cart_123",
      }),
    ).toBe("/us/en/cart");
  });
});
