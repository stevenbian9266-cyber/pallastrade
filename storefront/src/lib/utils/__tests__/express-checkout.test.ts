import type { Cart } from "@pallastrade/sdk";
import { describe, expect, it } from "vitest";
import {
  buildLineItems,
  expressAmount,
  expressLineItems,
  serverAmount,
  toCents,
} from "../express-checkout";

function baseCart(overrides: Partial<Cart> = {}): Cart {
  return {
    id: "cart_x",
    currency: "USD",
    item_total: "100.00",
    discount_total: null,
    additional_tax_total: null,
    express_payment: null,
    ...overrides,
  } as Cart;
}

describe("toCents", () => {
  it("multiplies by 100 for standard currencies", () => {
    expect(toCents("9.99", "USD")).toBe(999);
  });

  it("passes zero-decimal currencies through unchanged", () => {
    expect(toCents("1000", "JPY")).toBe(1000);
  });
});

// P0-4 (PRD FR-040/041): 权威金额只来自服务端 express_payment；前端不得重算。
describe("server-authoritative express amount", () => {
  it("serverAmount returns the server minor-unit amount when present", () => {
    const cart = baseCart({
      express_payment: {
        amount: 10000,
        currency: "USD",
        display_total: "$100.00",
        line_items: [{ name: "Subtotal", amount: 10000 }],
      },
    });

    expect(serverAmount(cart)).toBe(10000);
  });

  it("serverAmount returns null when the payload is absent", () => {
    expect(serverAmount(baseCart())).toBeNull();
  });

  it("expressAmount prefers the server amount over a client-side sum (FR-041)", () => {
    const cart = baseCart({
      express_payment: {
        amount: 10000,
        currency: "USD",
        display_total: "$100.00",
        // 展示行即使与实收不一致，也不得据此重算扣款金额
        line_items: [{ name: "Subtotal", amount: 9000 }],
      },
    });

    expect(expressAmount(cart)).toBe(10000);
  });

  it("expressAmount falls back to the legacy line-item sum when no payload exists", () => {
    expect(expressAmount(baseCart())).toBe(10000);
  });

  it("expressLineItems returns the server line items when present", () => {
    const serverItems = [
      { name: "Subtotal", amount: 10000 },
      { name: "Tax", amount: 800 },
    ];
    const cart = baseCart({
      express_payment: {
        amount: 10800,
        currency: "USD",
        display_total: "$108.00",
        line_items: serverItems,
      },
    });

    expect(expressLineItems(cart)).toEqual(serverItems);
  });

  it("expressLineItems falls back to buildLineItems when no payload exists", () => {
    expect(expressLineItems(baseCart())).toEqual([
      { name: "Subtotal", amount: 10000 },
    ]);
  });

  it("buildLineItems remains display-only and excludes shipping", () => {
    const items = buildLineItems(baseCart());
    expect(items.some((i) => i.name.toLowerCase().includes("shipping"))).toBe(
      false,
    );
  });
});
