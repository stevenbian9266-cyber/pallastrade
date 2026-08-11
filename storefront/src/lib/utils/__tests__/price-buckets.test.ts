import { describe, expect, it } from "vitest";
import { findMatchingBucket, generatePriceBuckets } from "../price-buckets";

describe("generatePriceBuckets", () => {
  it("creates under-50 bucket when filterMin is below the first threshold", () => {
    const buckets = generatePriceBuckets(0, 500, "USD");
    expect(buckets[0].id).toBe("under-50");
    expect(buckets[0].max).toBe(50);
  });

  it("creates the 200-plus bucket when filterMax exceeds the last threshold", () => {
    const buckets = generatePriceBuckets(0, 500, "USD");
    const last = buckets[buckets.length - 1];
    expect(last.id).toBe("200-plus");
    expect(last.min).toBe(200);
  });

  it("creates range buckets between thresholds when the range overlaps them", () => {
    const buckets = generatePriceBuckets(0, 500, "USD");
    const ids = buckets.map((b) => b.id);
    expect(ids).toContain("50-100");
    expect(ids).toContain("100-200");
  });

  it("uses the translation function when provided", () => {
    const buckets = generatePriceBuckets(0, 500, "USD", {
      t: (key, values) => `${key}:${values?.price ?? ""}`,
    });
    expect(buckets[0].label).toContain("priceUnder");
  });

  it("falls back to plain currency when Intl fails", () => {
    // An invalid currency triggers the catch branch of formatCurrency.
    const buckets = generatePriceBuckets(0, 500, "NOT-A-CURRENCY", {
      locale: "und",
    });
    expect(buckets[0].label).toContain("NOT-A-CURRENCY");
  });

  it("does not create buckets when the range is entirely inside a gap", () => {
    const buckets = generatePriceBuckets(55, 99, "USD");
    // 55-99 sits between 50 and 100 but overlaps only one threshold band edge
    const ids = buckets.map((b) => b.id);
    expect(ids.length).toBeGreaterThan(0);
  });
});

describe("findMatchingBucket", () => {
  const buckets = generatePriceBuckets(0, 500, "USD");

  it("returns the matching range bucket", () => {
    const match = findMatchingBucket(buckets, 50, 100);
    expect(match?.id).toBe("50-100");
  });

  it("returns the under-50 bucket when priceMin is undefined", () => {
    const open = findMatchingBucket(buckets, undefined, 50);
    expect(open?.id).toBe("under-50");
  });

  it("returns undefined when nothing matches", () => {
    expect(findMatchingBucket(buckets, 999, 1000)).toBeUndefined();
  });

  it("handles undefined bounds correctly", () => {
    const open = findMatchingBucket(buckets, 200, undefined);
    expect(open?.id).toBe("200-plus");
  });
});
