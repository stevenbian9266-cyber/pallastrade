import type { Product } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ProductCard } from "@/components/products/ProductCard";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@/contexts/StoreContext", () => ({
  useStore: () => ({ currency: "USD", locale: "en", loading: false }),
}));

/**
 * PRD-20260916-catalog-batch-f2-stock-shipping AC-015: the grid card shows the
 * scarcity bucket only when the API says so — and never breaks on products that
 * predate the field (older cached payloads carry no `stock_status`).
 */
function card(overrides: Record<string, unknown>): Product {
  return {
    id: "prod-1",
    name: "Classic T-Shirt",
    slug: "classic-t-shirt",
    purchasable: true,
    thumbnail_url: "https://example.com/shirt.jpg",
    price: {
      display_amount: "$25.00",
      amount_in_cents: 2500,
      compare_at_amount_in_cents: null,
      display_compare_at_amount: null,
    },
    original_price: { display_amount: "$25.00", amount_in_cents: 2500 },
    ...overrides,
  } as unknown as Product;
}

describe("ProductCard stock badge (F-2)", () => {
  it("shows the scarcity badge for the low-stock bucket", () => {
    render(<ProductCard product={card({ stock_status: "low_stock" })} />);

    expect(screen.getByTestId("stock-badge-low")).toBeTruthy();
    expect(screen.getByText("onlyFewLeft")).toBeTruthy();
  });

  it("stays quiet for a fully stocked product", () => {
    render(<ProductCard product={card({ stock_status: "in_stock" })} />);

    expect(screen.queryByTestId("stock-badge-low")).toBeNull();
  });

  it("renders without the field at all (older cached payloads)", () => {
    render(<ProductCard product={card({})} />);

    expect(screen.queryByTestId("stock-badge-low")).toBeNull();
    expect(screen.getByText("Classic T-Shirt")).toBeTruthy();
  });
});
