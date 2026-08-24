import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { OrderStatusTabs } from "@/components/account/OrderStatusTabs";

const tabs = [
  { key: "all", label: "All" },
  { key: "unpaid", label: "Unpaid" },
  { key: "processing", label: "Processing" },
  { key: "shipped", label: "Shipped" },
  { key: "completed", label: "Completed" },
  { key: "canceled", label: "Canceled" },
] as const;

// # PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台 AC-001
describe("OrderStatusTabs", () => {
  it("renders all status tabs with links", () => {
    render(
      <OrderStatusTabs tabs={[...tabs]} activeKey="all" basePath="/us/en" />,
    );

    for (const tab of tabs) {
      expect(screen.getByTestId(`order-tab-${tab.key}`)).toBeTruthy();
    }
  });

  it("links the all tab to the base orders path and others to ?status=", () => {
    render(
      <OrderStatusTabs tabs={[...tabs]} activeKey="all" basePath="/us/en" />,
    );

    expect(screen.getByTestId("order-tab-all").getAttribute("href")).toBe(
      "/us/en/account/orders",
    );
    expect(screen.getByTestId("order-tab-unpaid").getAttribute("href")).toBe(
      "/us/en/account/orders?status=unpaid",
    );
  });

  it("marks the active tab with aria-current and a distinct style", () => {
    render(
      <OrderStatusTabs
        tabs={[...tabs]}
        activeKey="processing"
        basePath="/us/en"
      />,
    );

    const active = screen.getByTestId("order-tab-processing");
    expect(active.getAttribute("aria-current")).toBe("page");
    expect(active.className).toContain("bg-gray-900");

    const inactive = screen.getByTestId("order-tab-unpaid");
    expect(inactive.getAttribute("aria-current")).toBeNull();
  });
});
