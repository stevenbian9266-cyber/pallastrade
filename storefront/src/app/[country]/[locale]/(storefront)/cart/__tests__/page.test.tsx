import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockCart = {
  id: "cart-1",
  number: "R1001",
  state: "cart",
  token: "tok-1",
  total_quantity: 2,
  item_total: "100.00",
  display_item_total: "$100.00",
  delivery_total: "0.00",
  display_delivery_total: "$0.00",
  tax_total: "0.00",
  display_tax_total: "$0.00",
  total: "100.00",
  display_total: "$100.00",
  amount_due: "100.00",
  display_amount_due: "$100.00",
  discount_total: "0.00",
  gift_card_total: "0.00",
  store_credit_total: "0.00",
  items: [
    {
      id: "li_1",
      name: "Product A",
      quantity: 2,
      display_price: "$50.00",
      options_text: "Red / M",
    },
  ],
};

vi.mock("next-intl", async () => {
  const actual = await vi.importActual("next-intl");
  return {
    ...actual,
    useTranslations: () => (key: string) => key,
  };
});

vi.mock("next/navigation", () => ({
  usePathname: () => "/us/en/cart",
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
}));

vi.mock("@/contexts/CartContext", () => ({
  useCart: () => ({
    cart: mockCart,
    loading: false,
    updateItem: vi.fn(),
    removeItem: vi.fn(),
  }),
}));

vi.mock("@/lib/analytics/gtm", () => ({
  trackViewCart: vi.fn(),
  trackRemoveFromCart: vi.fn(),
}));

vi.mock("next/dynamic", () => {
  const MockExpress = () => null;
  return {
    __esModule: true,
    default: (loader: unknown) => {
      void loader;
      return MockExpress;
    },
  };
});

vi.mock("@/components/ui/product-image", () => ({
  ProductImage: () => <div data-testid="product-image" />,
}));

// # PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 AC-012
// 公用订单确认页：购物车链路（Proceed to Checkout）与 Buy Now 指向同一 /checkout/{id} 确认页
import CartPage from "@/app/[country]/[locale]/(storefront)/cart/page";

describe("CartPage（公用确认页链路 A）", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("AC-012: 购物车结账跳转到公用确认页 /checkout/{cartId}", async () => {
    render(<CartPage />);

    const link = screen
      .getByText("proceedToCheckout")
      .closest("a") as HTMLAnchorElement;
    expect(link).toBeTruthy();
    // 与 Buy Now 同一确认页路由（/checkout/[id]），Buy Now 仅附加 ?from=buy-now
    expect(link.getAttribute("href")).toBe("/us/en/checkout/cart-1");
  });

  it("AC-012: 渲染购物车商品与数量", async () => {
    render(<CartPage />);

    expect(screen.getByText("Product A")).toBeTruthy();
    expect(screen.getByText("$50.00")).toBeTruthy();
  });
});
