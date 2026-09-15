import type { Product } from "@pallastrade/sdk";
import { describe, expect, it } from "vitest";
import {
  buildRelatedQuery,
  categoryIdsFor,
  pickRelated,
  RELATED_PRODUCTS_LIMIT,
} from "@/lib/utils/related-products";

function product(id: string): Product {
  return {
    id,
    name: `Product ${id}`,
    slug: `product-${id}`,
  } as unknown as Product;
}

describe("buildRelatedQuery (AC-001)", () => {
  it("targets the product's categories, buyable only, over-fetching by one", () => {
    expect(buildRelatedQuery(["cat_1", "cat_2"])).toEqual({
      in_categories: ["cat_1", "cat_2"],
      in_stock: true,
      limit: RELATED_PRODUCTS_LIMIT + 1,
      sort: "-available_on",
    });
  });

  it("honours a custom limit and sort", () => {
    expect(buildRelatedQuery(["cat_1"], { limit: 4, sort: "price" })).toEqual({
      in_categories: ["cat_1"],
      in_stock: true,
      limit: 5,
      sort: "price",
    });
  });
});

describe("categoryIdsFor", () => {
  it("de-duplicates and drops blank ids", () => {
    expect(
      categoryIdsFor({
        categories: [{ id: "cat_1" }, { id: "cat_1" }, { id: "" }],
      } as unknown as Product),
    ).toEqual(["cat_1"]);
  });

  it("returns an empty list when the product has no categories", () => {
    expect(categoryIdsFor(null)).toEqual([]);
    expect(
      categoryIdsFor({ categories: undefined } as unknown as Product),
    ).toEqual([]);
  });
});

describe("pickRelated (AC-001)", () => {
  it("drops the excluded product and trims the over-fetch", () => {
    const products = ["1", "2", "3", "4"].map(product);

    expect(
      pickRelated(products, { excludeIds: ["2"], limit: 2 }).map((p) => p.id),
    ).toEqual(["1", "3"]);
  });

  it("ignores empty exclusions and keeps the requested limit by default", () => {
    const products = Array.from(
      { length: RELATED_PRODUCTS_LIMIT + 2 },
      (_, i) => product(String(i + 1)),
    );

    expect(
      pickRelated(products, { excludeIds: [null, undefined] }),
    ).toHaveLength(RELATED_PRODUCTS_LIMIT);
  });

  it("returns an empty list when everything is excluded", () => {
    expect(pickRelated([product("1")], { excludeIds: ["1"] })).toEqual([]);
  });
});
