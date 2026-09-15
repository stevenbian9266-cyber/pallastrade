import type { Product } from "@pallastrade/sdk";
import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { WishlistList } from "@/app/[country]/[locale]/(storefront)/wishlist/WishlistList";
import {
  parseWishlist,
  serializeWishlist,
  WISHLIST_KEY,
  type WishlistEntry,
} from "@/lib/utils/wishlist";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@/components/products/ProductCard", () => ({
  ProductCard: ({ product }: { product: Product }) => (
    <span data-testid="wishlist-card">{product.name}</span>
  ),
}));

function product(id: string): Product {
  return {
    id,
    name: `Product ${id}`,
    slug: `product-${id}`,
  } as unknown as Product;
}

function entry(id: string): WishlistEntry {
  return { id, slug: `product-${id}`, addedAt: 1, product: product(id) };
}

describe("WishlistList (AC-008)", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("shows the empty state with a way back to the catalog", () => {
    render(<WishlistList basePath="/us/en" />);

    expect(screen.getByTestId("wishlist-empty")).toBeTruthy();
    expect(screen.getByText("empty")).toBeTruthy();
  });

  it("renders saved products and removes one on demand", () => {
    window.localStorage.setItem(
      WISHLIST_KEY,
      serializeWishlist([entry("1"), entry("2")]),
    );

    render(<WishlistList basePath="/us/en" />);

    expect(screen.getAllByTestId("wishlist-card")).toHaveLength(2);

    fireEvent.click(screen.getAllByText("remove")[0]);

    expect(screen.getAllByTestId("wishlist-card")).toHaveLength(1);
    expect(
      parseWishlist(window.localStorage.getItem(WISHLIST_KEY)).map((e) => e.id),
    ).toEqual(["2"]);
  });

  it("re-renders the empty state after removing the last entry", () => {
    window.localStorage.setItem(WISHLIST_KEY, serializeWishlist([entry("1")]));

    render(<WishlistList basePath="/us/en" />);
    fireEvent.click(screen.getByText("remove"));

    expect(screen.getByTestId("wishlist-empty")).toBeTruthy();
  });
});
