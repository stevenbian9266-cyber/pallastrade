import type { Product } from "@pallastrade/sdk";
import { render } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";
import { ProductCarousel } from "@/components/products/ProductCarousel";

/**
 * PRD-20260916-shipping-catalog-observability-scope AC-008/AC-009 (mechanism):
 * one carousel serves every rail, and it used to hard-code `featured-products`
 * / `Featured Products` — so Related and Recently Viewed clicks were reported
 * as Featured clicks. The rail id must come from the caller, with Featured as
 * the default so the home rail needs no change.
 */

const cardProps: Array<Record<string, unknown>> = [];

vi.mock("swiper/react", () => ({
  Swiper: ({ children }: { children: ReactNode }) => <div>{children}</div>,
  SwiperSlide: ({ children }: { children: ReactNode }) => <div>{children}</div>,
}));
vi.mock("swiper/modules", () => ({ Navigation: {} }));
vi.mock("swiper/css", () => ({}));
vi.mock("swiper/css/navigation", () => ({}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@/components/products/ProductCard", () => ({
  ProductCard: (props: Record<string, unknown>) => {
    cardProps.push(props);
    return <div>{String((props.product as Product).name)}</div>;
  },
}));

function product(id: string): Product {
  return {
    id,
    name: `Product ${id}`,
    slug: `product-${id}`,
  } as unknown as Product;
}

describe("ProductCarousel list identity", () => {
  it("defaults to the featured list so the home rail keeps its attribution", () => {
    cardProps.length = 0;

    render(
      <ProductCarousel
        products={[product("1")]}
        basePath="/us/en"
        currency="USD"
      />,
    );

    expect(cardProps[0]?.listId).toBe("featured-products");
    expect(cardProps[0]?.listName).toBe("Featured Products");
  });

  it("passes the caller's list id through to every card (AC-008/AC-009)", () => {
    cardProps.length = 0;

    render(
      <ProductCarousel
        products={[product("1"), product("2")]}
        basePath="/us/en"
        currency="USD"
        listId="related-products"
        listName="Related Products"
      />,
    );

    expect(cardProps).toHaveLength(2);
    expect(cardProps.every((p) => p.listId === "related-products")).toBe(true);
    expect(cardProps.every((p) => p.listName === "Related Products")).toBe(
      true,
    );
  });
});
