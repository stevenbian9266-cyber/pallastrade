import type { Order } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { OrderDetail } from "@/components/account/OrderDetail";

/**
 * PRD-20260919-checkout-express-always-visible-and-pi-params AC-005（FR-004）：
 * 详情组件要能渲染**待支付**订单 ——
 *   ① 时间行回落到 `submitted_at`（`completed_at` 为 null 不再显示 "-"）；
 *   ② 保留 `OrderPayButton` 作为补付入口（payable → Pay Now）。
 * `OrderDetail` 是 async server component，这里按 RSC 惯例直接调用后渲染结果。
 */

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string, values?: unknown) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@/components/account/OrderPayButton", () => ({
  OrderPayButton: ({ order }: { order: { id: string } }) => (
    <div data-testid="order-pay-button">{order.id}</div>
  ),
}));

function unpaidOrder(): Order {
  return {
    id: "or_X35bb5HTmV",
    number: "R729701382",
    email: "pallastrade@example.com",
    currency: "USD",
    state: "pending",
    status: "placed",
    payment_status: "",
    submitted_at: "2026-09-19T14:30:37Z",
    completed_at: null,
    total_quantity: 1,
    items: [],
    fulfillments: [],
    payments: [],
    discounts: [],
    children_ids: [],
    display_total: "$129.99",
    display_item_total: "$129.99",
    display_delivery_total: "$0.00",
  } as unknown as Order;
}

async function renderDetail(order: Order) {
  const view = await OrderDetail({ order, basePath: "/us/en", locale: "en" });
  render(view);
}

describe("OrderDetail for unpaid orders (AC-005)", () => {
  it("renders the detail with a Pay Now entry for an unpaid order", async () => {
    await renderDetail(unpaidOrder());

    expect(screen.getByTestId("order-pay-button").textContent).toBe(
      "or_X35bb5HTmV",
    );
    expect(screen.getByText('orderTitle:{"number":"R729701382"}')).toBeTruthy();
  });

  it("falls back to the submitted date when completed_at is missing", async () => {
    await renderDetail(unpaidOrder());

    const placedOn = screen.getByText(/^placedOn:/);
    // 不是占位符 "-"（旧行为：未支付订单显示空日期），而是真实下单时间
    expect(placedOn.textContent).not.toContain('"date":"-"');
    expect(placedOn.textContent).toMatch(/2026/);
  });

  it("prefers completed_at when the order is completed", async () => {
    const completed = {
      ...unpaidOrder(),
      completed_at: "2026-09-20T08:00:00Z",
      state: "complete",
    } as unknown as Order;

    await renderDetail(completed);

    const placedOn = screen.getByText(/^placedOn:/);
    expect(placedOn.textContent).toContain("2026");
    expect(placedOn.textContent).not.toContain("2026-09-19T14:30:37Z");
  });
});
