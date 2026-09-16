import { describe, expect, it } from "vitest";
import {
  addBusinessDays,
  estimatedArrivalRange,
  formatArrivalRange,
} from "../arrival";

/**
 * PRD-20260916-catalog-batch-f2-stock-shipping AC-008: transit windows are
 * counted in weekdays (Mon–Fri, no holiday calendar), and the arrival range
 * must survive weekends and month boundaries.
 */
describe("addBusinessDays", () => {
  it("skips the weekend", () => {
    // Friday 2026-09-18 → +1 business day = Monday 2026-09-21
    expect(addBusinessDays(new Date(2026, 8, 18), 1).getDate()).toBe(21);
  });

  it("crosses a month boundary without drifting", () => {
    // Wednesday 2026-09-30 → +2 business days = Friday 2026-10-02
    const result = addBusinessDays(new Date(2026, 8, 30), 2);
    expect(result.getMonth()).toBe(9);
    expect(result.getDate()).toBe(2);
  });

  it("treats zero days as the same date", () => {
    const from = new Date(2026, 8, 16);
    expect(addBusinessDays(from, 0).getDate()).toBe(from.getDate());
  });
});

describe("estimatedArrivalRange", () => {
  it("returns null when neither bound is published", () => {
    expect(estimatedArrivalRange(null, null)).toBeNull();
  });

  it("collapses a single published bound into one day", () => {
    const range = estimatedArrivalRange(3, null, new Date(2026, 8, 16));
    expect(range).not.toBeNull();
    expect(range?.sameDay).toBe(true);
  });

  it("widens to the published maximum", () => {
    const range = estimatedArrivalRange(3, 5, new Date(2026, 8, 16));
    expect(range?.sameDay).toBe(false);
    expect(range?.to.getTime()).toBeGreaterThan(range?.from.getTime() ?? 0);
  });
});

describe("formatArrivalRange", () => {
  it("renders one date when both ends match", () => {
    const range = estimatedArrivalRange(2, 2, new Date(2026, 8, 16));
    const label = formatArrivalRange(range!, "en");
    expect(label).toMatch(/Sep/);
    expect(label).not.toMatch(/–/);
  });

  it("is locale-aware (same range, different output)", () => {
    const range = estimatedArrivalRange(3, 5, new Date(2026, 8, 16));
    const en = formatArrivalRange(range!, "en");
    const de = formatArrivalRange(range!, "de");

    expect(en).not.toBe(de);
    expect(en.length).toBeGreaterThan(0);
    expect(de.length).toBeGreaterThan(0);
  });
});
