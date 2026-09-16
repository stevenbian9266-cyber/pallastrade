import type { Product } from "@pallastrade/sdk";
import { render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { RelatedProducts } from "@/components/products/RelatedProducts";

/**
 * PRD-20260916-shipping-商品域收口批次 AC-008: the related rail must attribute
 * its clicks to itself. `ProductCarousel` used to hard-code
 * `featured-products` / `Featured Products`, so every click in this rail was
 * counted as a Featured click (worse than no attribution at all).
 */

const carouselProps: Array<Record<string, unknown>> = [];

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

vi.mock("@/lib/data/products", () => ({
  getRelatedProducts: vi.fn(async () => [product("1")]),
}));

// The Swiper bundle is irrelevant here and unfriendly to jsdom — capture the
// props the rail hands down instead.
vi.mock("@/components/products/LazyProductCarousel", () => ({
  LazyProductCarousel: (props: Record<string, unknown>) => {
    carouselProps.push(props);
    return null;
  },
}));

function product(id: string): Product {
  return {
    id,
    name: `Product ${id}`,
    slug: `product-${id}`,
    categories: [{ id: "cat_1", name: "Category" }],
  } as unknown as Product;
}

describe("RelatedProducts rail identity (AC-008)", () => {
  it("hands its own list id to the carousel instead of Featured's", async () => {
    carouselProps.length = 0;

    render(
      await RelatedProducts({
        product: product("main"),
        basePath: "/us/en",
        locale: "en",
        country: "us",
        currency: "USD",
      }),
    );

    expect(carouselProps[0]?.listId).toBe("related-products");
    expect(carouselProps[0]?.listName).toBe("Related Products");
  });
});
