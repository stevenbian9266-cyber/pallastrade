import { describe, it, expect } from "vitest";
import { buildProductQueryParams, wrapInRansackParams } from "../product-query";
import type { ActiveFilters } from "@/types/filters";

function baseFilters(overrides: Partial<ActiveFilters> = {}): ActiveFilters {
  return {
    priceMin: undefined,
    priceMax: undefined,
    optionValues: [],
    availability: undefined,
    sortBy: undefined,
    ...overrides,
  };
}

describe("buildProductQueryParams", () => {
  it("sets search when a query is provided", () => {
    expect(buildProductQueryParams(baseFilters(), "shirt").search).toBe("shirt");
  });

  it("maps price bounds to gte/lte params", () => {
    const params = buildProductQueryParams(
      baseFilters({ priceMin: 10, priceMax: 100 }),
    );
    expect(params.price_gte).toBe(10);
    expect(params.price_lte).toBe(100);
  });

  it("maps option values to with_option_value_ids", () => {
    const params = buildProductQueryParams(
      baseFilters({ optionValues: ["ov1", "ov2"] }),
    );
    expect(params.with_option_value_ids).toEqual(["ov1", "ov2"]);
  });

  it("maps availability to in_stock / out_of_stock", () => {
    expect(
      buildProductQueryParams(baseFilters({ availability: "in_stock" })).in_stock,
    ).toBe(true);
    expect(
      buildProductQueryParams(baseFilters({ availability: "out_of_stock" }))
        .out_of_stock,
    ).toBe(true);
    const none = buildProductQueryParams(baseFilters());
    expect(none.in_stock).toBeUndefined();
    expect(none.out_of_stock).toBeUndefined();
  });

  it("maps sortBy except manual", () => {
    expect(buildProductQueryParams(baseFilters({ sortBy: "price" })).sort).toBe(
      "price",
    );
    expect(
      buildProductQueryParams(baseFilters({ sortBy: "manual" })).sort,
    ).toBeUndefined();
  });
});

describe("wrapInRansackParams", () => {
  it("skips undefined values", () => {
    expect(wrapInRansackParams({ a: undefined, b: 1 })).toEqual({ "q[b]": 1 });
  });

  it("keeps already-wrapped keys", () => {
    expect(wrapInRansackParams({ "q[term]": "x" })).toEqual({ "q[term]": "x" });
  });

  it("wraps arrays with empty brackets", () => {
    expect(wrapInRansackParams({ ids: [1, 2] })).toEqual({ "q[ids][]": [1, 2] });
  });

  it("wraps scalars in q[...]", () => {
    expect(wrapInRansackParams({ price_gte: 10 })).toEqual({ "q[price_gte]": 10 });
  });
});
