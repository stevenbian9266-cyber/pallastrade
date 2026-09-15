import type { Product } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { RecentlyViewed } from "@/components/products/RecentlyViewed";
import {
  RECENTLY_VIEWED_KEY,
  type RecentlyViewedEntry,
  serializeRecentlyViewed,
} from "@/lib/utils/recently-viewed";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

// The rail itself is a Swiper wrapper — irrelevant here and unfriendly to jsdom.
vi.mock("@/components/products/ProductCarousel", () => ({
  ProductCarousel: ({ products }: { products: Product[] }) => (
    <ul data-testid="rail">
      {products.map((item) => (
        <li key={item.id}>{item.name}</li>
      ))}
    </ul>
  ),
}));

function product(id: string): Product {
  return {
    id,
    name: `Product ${id}`,
    slug: `product-${id}`,
  } as unknown as Product;
}

function entry(id: string): RecentlyViewedEntry {
  return { id, slug: `product-${id}`, viewedAt: 1, product: product(id) };
}

describe("RecentlyViewed (AC-004/AC-011)", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("renders nothing when there is no history (first paint is empty by design)", () => {
    const { container } = render(<RecentlyViewed basePath="/us/en" />);

    expect(container.firstChild).toBeNull();
  });

  it("renders stored products after mount", () => {
    window.localStorage.setItem(
      RECENTLY_VIEWED_KEY,
      serializeRecentlyViewed([entry("1"), entry("2")]),
    );

    render(<RecentlyViewed basePath="/us/en" />);

    expect(screen.getByText("Product 2")).toBeTruthy();
    expect(screen.getByText("Product 1")).toBeTruthy();
  });

  it("never suggests the product the shopper is already looking at", () => {
    window.localStorage.setItem(
      RECENTLY_VIEWED_KEY,
      serializeRecentlyViewed([entry("1"), entry("2")]),
    );

    render(<RecentlyViewed basePath="/us/en" currentProductId="1" />);

    expect(screen.queryByText("Product 1")).toBeNull();
    expect(screen.getByText("Product 2")).toBeTruthy();
  });

  it("ignores corrupt storage", () => {
    window.localStorage.setItem(RECENTLY_VIEWED_KEY, "{not json");

    const { container } = render(<RecentlyViewed basePath="/us/en" />);

    expect(container.firstChild).toBeNull();
  });
});
