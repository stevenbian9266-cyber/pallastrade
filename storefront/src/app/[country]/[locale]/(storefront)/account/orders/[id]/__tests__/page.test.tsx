import type { Order } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import OrderDetailPage from "@/app/[country]/[locale]/(storefront)/account/orders/[id]/page";

/**
 * PRD-20260919-checkout-express-always-visible-and-pi-params AC-005（FR-004）：
 * 页面层只负责「取不到订单才 not found」——待支付订单（`completed_at === null`）
 * 必须照常进入详情渲染（详情内部的时间回退与 Pay Now 由 `OrderDetail` 用例覆盖，
 * 那里用真实组件）。
 */

const getOrderMock = vi.fn();
const orderDetailProps = vi.fn();

vi.mock("next/server", () => ({
  connection: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

vi.mock("@/lib/data/orders", () => ({
  getOrder: (...args: unknown[]) => getOrderMock(...args),
}));

// 详情是 async server component（jsdom 不能直接渲染），页面层用探针替身即可 ——
// 真实渲染口径由 `components/account/__tests__/OrderDetail.test.tsx` 覆盖。
vi.mock("@/components/account/OrderDetail", () => ({
  OrderDetail: (props: Record<string, unknown>) => {
    orderDetailProps(props);
    return (
      <div data-testid="order-detail">{(props.order as { id: string }).id}</div>
    );
  },
}));

/** 待支付订单：`submitted_at` 有值、`completed_at` 为 null（事故订单口径）。 */
const unpaidOrder = {
  id: "or_X35bb5HTmV",
  number: "R729701382",
  state: "pending",
  status: "placed",
  payment_status: "",
  submitted_at: "2026-09-19T14:30:37Z",
  completed_at: null,
} as unknown as Order;

function renderPage(id = "or_X35bb5HTmV") {
  return OrderDetailPage({
    params: Promise.resolve({ country: "us", locale: "en", id }),
  }).then((view) => render(view));
}

describe("order detail page (AC-005)", () => {
  beforeEach(() => {
    getOrderMock.mockReset();
    orderDetailProps.mockReset();
  });

  it("renders an order that was not completed yet instead of not-found", async () => {
    getOrderMock.mockResolvedValue(unpaidOrder);

    await renderPage();

    expect(screen.getByTestId("order-detail").textContent).toBe(
      "or_X35bb5HTmV",
    );
    expect(screen.queryByText("orderNotFound")).toBeNull();
    // 页面把完整订单与站点前缀交给详情组件（详情内部渲染 Pay Now）
    expect(orderDetailProps.mock.calls.at(-1)?.[0]).toMatchObject({
      basePath: "/us/en",
      locale: "en",
    });
  });

  it("still shows not-found when the order cannot be retrieved", async () => {
    getOrderMock.mockResolvedValue(null);

    await renderPage("or_missing");

    expect(screen.getByText("orderNotFound")).toBeTruthy();
    expect(screen.getByText("orderNotFoundDescription")).toBeTruthy();
    expect(screen.queryByTestId("order-detail")).toBeNull();
  });
});
