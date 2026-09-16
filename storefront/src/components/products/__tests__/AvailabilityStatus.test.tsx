import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { AvailabilityStatus } from "../AvailabilityStatus";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
  useLocale: () => "en",
}));

/**
 * PRD-20260916-catalog-batch-f2-stock-shipping AC-010: the PDP stock line keeps
 * all five buckets readable, and the 4.2 states (pre-order ship-by, backorder
 * note) are untouched by the new low-stock branch.
 */
describe("AvailabilityStatus", () => {
  it("stays quiet for a plain in-stock product", () => {
    render(
      <AvailabilityStatus availability="in_stock" stockStatus="in_stock" />,
    );

    expect(screen.getByText("inStock")).toBeTruthy();
    expect(screen.queryByTestId("stock-badge-low")).toBeNull();
  });

  it("swaps to the scarcity line for the low-stock bucket", () => {
    render(
      <AvailabilityStatus availability="in_stock" stockStatus="low_stock" />,
    );

    expect(screen.getByTestId("stock-badge-low")).toBeTruthy();
    expect(screen.getByText("onlyFewLeft")).toBeTruthy();
    expect(screen.queryByText("inStock")).toBeNull();
  });

  it("ignores the bucket for states that already speak for themselves", () => {
    render(
      <AvailabilityStatus availability="backorder" stockStatus="low_stock" />,
    );

    expect(screen.getByText("backorder")).toBeTruthy();
    expect(screen.queryByTestId("stock-badge-low")).toBeNull();
  });

  it("keeps the pre-order ship-by promise (4.2 regression)", () => {
    render(
      <AvailabilityStatus
        availability="preorder"
        preorderShipsAt="2026-10-01T00:00:00Z"
        stockStatus="preorder"
      />,
    );

    expect(screen.getByText("preorder")).toBeTruthy();
    expect(screen.getByText(/preorderShipsBy/)).toBeTruthy();
  });

  it("keeps the sold-out line", () => {
    render(
      <AvailabilityStatus
        availability="out_of_stock"
        stockStatus="out_of_stock"
      />,
    );

    expect(screen.getByText("outOfStock")).toBeTruthy();
  });

  it("does not render a scarcity badge when no bucket is supplied", () => {
    render(<AvailabilityStatus availability="in_stock" />);

    expect(screen.queryByTestId("stock-badge-low")).toBeNull();
  });
});
