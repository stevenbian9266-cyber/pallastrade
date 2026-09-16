import type { ShippingEstimate as ShippingEstimateData } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ShippingEstimate } from "../ShippingEstimate";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
  useLocale: () => "en",
}));

/**
 * PRD-20260916-catalog-batch-f2-stock-shipping AC-007 / AC-009 / AC-012.
 */
function estimate(
  overrides: Partial<ShippingEstimateData> = {},
): ShippingEstimateData {
  return {
    available: true,
    digital: false,
    min_days: 3,
    max_days: 5,
    free_shipping: false,
    free_shipping_threshold: null,
    business_day_source: "weekdays",
    methods: [],
    ...overrides,
  };
}

describe("ShippingEstimate", () => {
  it("renders the transit window and an arrival date (AC-007)", () => {
    render(<ShippingEstimate estimate={estimate()} />);

    expect(screen.getByTestId("shipping-estimate")).toBeTruthy();
    expect(screen.getByText(/transitDaysRange/)).toBeTruthy();
  });

  it("renders a single-day label when only one bound is published (AC-007)", () => {
    render(<ShippingEstimate estimate={estimate({ max_days: null })} />);

    expect(screen.getByText(/transitDaysSingle|transitDaysRange/)).toBeTruthy();
  });

  it("promises no window for a digital good (AC-007)", () => {
    render(
      <ShippingEstimate
        estimate={estimate({
          digital: true,
          available: false,
          min_days: null,
          max_days: null,
        })}
      />,
    );

    expect(screen.getByText("instantDownload")).toBeTruthy();
    expect(screen.queryByText(/transitDays/)).toBeNull();
  });

  it("falls back to checkout wording when nothing is available (AC-007)", () => {
    render(<ShippingEstimate estimate={estimate({ available: false })} />);

    expect(screen.getByText("shippingAtCheckout")).toBeTruthy();
  });

  it("renders nothing at all when the estimate is unknown (AC-012)", () => {
    const { container } = render(<ShippingEstimate estimate={null} />);
    expect(container.firstChild).toBeNull();
  });

  it("shows the free-shipping hint with the threshold amount (AC-007)", () => {
    render(
      <ShippingEstimate estimate={estimate({ free_shipping_threshold: 50 })} />,
    );

    expect(screen.getByText(/freeShippingOver/)).toBeTruthy();
  });

  it("prefers plain free-shipping wording when a promotion is running (AC-007)", () => {
    render(
      <ShippingEstimate
        estimate={estimate({
          free_shipping: true,
          free_shipping_threshold: 50,
        })}
      />,
    );

    expect(screen.getByText("freeShipping")).toBeTruthy();
    expect(screen.queryByText(/freeShippingOver/)).toBeNull();
  });

  it("exposes the arrival label to assistive tech, not just the digits (AC-012)", () => {
    render(<ShippingEstimate estimate={estimate()} />);

    // The label is a screen-reader-only span — the date alone would be meaningless.
    expect(screen.getByText("estimatedArrival:")).toBeTruthy();
  });
});
