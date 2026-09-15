import type { Product } from "@pallastrade/sdk";
import { describe, expect, it } from "vitest";
import {
  isWishlisted,
  parseWishlist,
  removeWishlistEntry,
  serializeWishlist,
  toggleWishlistEntry,
  WISHLIST_LIMIT,
  type WishlistEntry,
} from "@/lib/utils/wishlist";

function product(id: string): Product {
  return {
    id,
    name: `Product ${id}`,
    slug: `product-${id}`,
  } as unknown as Product;
}

function entry(id: string, addedAt = 1): WishlistEntry {
  return { id, slug: `product-${id}`, addedAt, product: product(id) };
}

describe("parseWishlist (AC-006)", () => {
  it("degrades to an empty list for missing or corrupt payloads", () => {
    expect(parseWishlist(null)).toEqual([]);
    expect(parseWishlist("{")).toEqual([]);
    expect(parseWishlist('{"id":"1"}')).toEqual([]);
    expect(parseWishlist('[{"slug":1}]')).toEqual([]);
  });

  it("caps the restored list", () => {
    const raw = serializeWishlist(
      Array.from({ length: WISHLIST_LIMIT + 2 }, (_, i) => entry(String(i))),
    );

    expect(parseWishlist(raw)).toHaveLength(WISHLIST_LIMIT);
  });
});

describe("toggleWishlistEntry (AC-006)", () => {
  it("saves a product at the front", () => {
    const next = toggleWishlistEntry([entry("a")], product("b"), { now: 9 });

    expect(next.map((e) => e.id)).toEqual(["b", "a"]);
    expect(next[0].addedAt).toBe(9);
  });

  it("removes a product that is already saved", () => {
    const next = toggleWishlistEntry([entry("a"), entry("b")], product("a"));

    expect(next.map((e) => e.id)).toEqual(["b"]);
  });

  it("never exceeds the cap", () => {
    const existing = Array.from({ length: WISHLIST_LIMIT }, (_, i) =>
      entry(String(i)),
    );
    const next = toggleWishlistEntry(existing, product("new"));

    expect(next).toHaveLength(WISHLIST_LIMIT);
    expect(next[0].id).toBe("new");
  });
});

describe("isWishlisted / removeWishlistEntry (AC-006)", () => {
  it("matches on the stringified id and tolerates blanks", () => {
    expect(isWishlisted([entry("1")], 1)).toBe(true);
    expect(isWishlisted([entry("1")], "2")).toBe(false);
    expect(isWishlisted([entry("1")], null)).toBe(false);
  });

  it("removes by id and leaves the list untouched for blanks", () => {
    expect(
      removeWishlistEntry([entry("1"), entry("2")], "1").map((e) => e.id),
    ).toEqual(["2"]);
    expect(removeWishlistEntry([entry("1")], undefined)).toHaveLength(1);
  });
});
