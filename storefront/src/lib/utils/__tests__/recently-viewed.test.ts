import type { Product } from "@pallastrade/sdk";
import { describe, expect, it } from "vitest";
import {
  parseRecentlyViewed,
  pushRecentlyViewed,
  RECENTLY_VIEWED_LIMIT,
  type RecentlyViewedEntry,
  serializeRecentlyViewed,
} from "@/lib/utils/recently-viewed";

function product(id: string): Product {
  return {
    id,
    name: `Product ${id}`,
    slug: `product-${id}`,
  } as unknown as Product;
}

function entry(id: string, viewedAt = 1): RecentlyViewedEntry {
  return { id, slug: `product-${id}`, viewedAt, product: product(id) };
}

describe("parseRecentlyViewed (AC-003)", () => {
  it("degrades to an empty list for missing, corrupt or foreign payloads", () => {
    expect(parseRecentlyViewed(null)).toEqual([]);
    expect(parseRecentlyViewed(undefined)).toEqual([]);
    expect(parseRecentlyViewed("")).toEqual([]);
    expect(parseRecentlyViewed("not json")).toEqual([]);
    expect(parseRecentlyViewed('"a string"')).toEqual([]);
    expect(parseRecentlyViewed("[1,2,3]")).toEqual([]);
    expect(parseRecentlyViewed('[{"id":"1"}]')).toEqual([]);
  });

  it("keeps valid entries and caps the restored list", () => {
    const raw = serializeRecentlyViewed(
      Array.from({ length: RECENTLY_VIEWED_LIMIT + 3 }, (_, i) =>
        entry(String(i)),
      ),
    );

    expect(parseRecentlyViewed(raw)).toHaveLength(RECENTLY_VIEWED_LIMIT);
  });
});

describe("pushRecentlyViewed (AC-003/AC-005)", () => {
  it("records a new visit at the front", () => {
    const next = pushRecentlyViewed([entry("a")], product("b"), { now: 42 });

    expect(next.map((e) => e.id)).toEqual(["b", "a"]);
    expect(next[0].viewedAt).toBe(42);
  });

  it("moves a repeated visit to the front without duplicating it", () => {
    const next = pushRecentlyViewed(
      [entry("a"), entry("b"), entry("c")],
      product("b"),
      {
        now: 7,
      },
    );

    expect(next.map((e) => e.id)).toEqual(["b", "a", "c"]);
    expect(next).toHaveLength(3);
  });

  it("drops the oldest entry once the cap is reached", () => {
    const existing = Array.from({ length: RECENTLY_VIEWED_LIMIT }, (_, i) =>
      entry(String(i)),
    );
    const next = pushRecentlyViewed(existing, product("new"));

    expect(next).toHaveLength(RECENTLY_VIEWED_LIMIT);
    expect(next[0].id).toBe("new");
    expect(next.some((e) => e.id === String(RECENTLY_VIEWED_LIMIT - 1))).toBe(
      false,
    );
  });
});

describe("serializeRecentlyViewed", () => {
  it("round-trips through parse", () => {
    const entries = [entry("a", 5), entry("b", 4)];

    expect(parseRecentlyViewed(serializeRecentlyViewed(entries))).toEqual(
      entries,
    );
  });
});
