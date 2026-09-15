import type { Product } from "@pallastrade/sdk";
import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { WishlistButton } from "@/components/products/WishlistButton";
import {
  parseWishlist,
  serializeWishlist,
  WISHLIST_KEY,
} from "@/lib/utils/wishlist";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

const product = {
  id: "prod-1",
  name: "Classic T-Shirt",
  slug: "classic-t-shirt",
} as unknown as Product;

function storedIds(): string[] {
  return parseWishlist(window.localStorage.getItem(WISHLIST_KEY)).map(
    (e) => e.id,
  );
}

describe("WishlistButton (AC-007)", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("renders unsaved, saves on click and persists the entry", () => {
    render(<WishlistButton product={product} />);
    const button = screen.getByRole("button");

    expect(button.getAttribute("aria-pressed")).toBe("false");
    expect(button.getAttribute("aria-label")).toBe("add");

    fireEvent.click(button);

    expect(button.getAttribute("aria-pressed")).toBe("true");
    expect(button.getAttribute("aria-label")).toBe("removeAria");
    expect(storedIds()).toEqual(["prod-1"]);
  });

  it("toggles back off on a second click", () => {
    render(<WishlistButton product={product} />);
    const button = screen.getByRole("button");

    fireEvent.click(button);
    fireEvent.click(button);

    expect(button.getAttribute("aria-pressed")).toBe("false");
    expect(storedIds()).toEqual([]);
  });

  it("starts saved when the product is already in the wishlist", () => {
    window.localStorage.setItem(
      WISHLIST_KEY,
      serializeWishlist([
        { id: "prod-1", slug: "classic-t-shirt", addedAt: 1, product },
      ]),
    );

    render(<WishlistButton product={product} />);

    expect(screen.getByRole("button").getAttribute("aria-pressed")).toBe(
      "true",
    );
  });
});
