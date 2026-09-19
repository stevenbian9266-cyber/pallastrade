import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * PRD-20260919-checkout-remove-items-block-mobile-summary-meta
 * AC-003 ~ AC-006：移动端 order summary 折叠按钮的「件数 + 金额」文案、
 * 展开态文案、无元数据回退、以及摘要内容为空时不渲染。
 */

const contextState = vi.hoisted(() => ({
  summaryContent: "summary" as unknown,
  summaryMeta: null as {
    itemCount: number;
    displayTotal: string | null;
  } | null,
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

vi.mock("next/navigation", () => ({
  usePathname: () => "/us/en/checkout/cart_1",
}));

vi.mock("@/lib/store", () => ({ getStoreName: () => "Test Store" }));

vi.mock("@/contexts/CheckoutContext", () => ({
  useCheckout: () => ({
    summaryContent: contextState.summaryContent,
    summaryMeta: contextState.summaryMeta,
  }),
  CheckoutSummary: () => <div data-testid="summary-panel" />,
}));

import { MobileSummaryToggle } from "../layout";

describe("MobileSummaryToggle (PRD-20260919-checkout-remove-items-block-mobile-summary-meta)", () => {
  beforeEach(() => {
    contextState.summaryContent = "summary";
    contextState.summaryMeta = { itemCount: 3, displayTotal: "$129.99" };
  });

  // AC-003
  it("shows item count and amount while collapsed", () => {
    render(<MobileSummaryToggle />);

    expect(screen.getByRole("button").textContent).toContain(
      'showOrderSummaryWithMeta:{"count":3,"amount":"$129.99"}',
    );
  });

  // AC-004
  it("shows the plain hide label when expanded", async () => {
    const user = userEvent.setup();
    render(<MobileSummaryToggle />);

    await user.click(screen.getByRole("button"));

    const label = screen.getByRole("button").textContent ?? "";
    expect(label).toContain("hideOrderSummary");
    expect(label).not.toContain("showOrderSummaryWithMeta");
    expect(screen.getByTestId("summary-panel")).toBeInTheDocument();
  });

  // AC-005
  it("falls back to the plain label without metadata or amount", () => {
    contextState.summaryMeta = null;
    const { unmount } = render(<MobileSummaryToggle />);
    expect(screen.getByRole("button").textContent).toContain(
      "showOrderSummary",
    );
    expect(screen.getByRole("button").textContent).not.toContain(
      "showOrderSummaryWithMeta",
    );
    unmount();

    contextState.summaryMeta = { itemCount: 3, displayTotal: null };
    render(<MobileSummaryToggle />);
    expect(screen.getByRole("button").textContent).toContain(
      "showOrderSummary",
    );
    expect(screen.getByRole("button").textContent).not.toContain("undefined");
  });

  // AC-006
  it("renders nothing when the summary content is cleared", () => {
    contextState.summaryContent = null;
    render(<MobileSummaryToggle />);

    expect(screen.queryByRole("button")).toBeNull();
  });
});
