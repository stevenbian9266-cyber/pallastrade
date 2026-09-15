import type { Order, PaymentSession } from "@pallastrade/sdk";
import { render, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import PaymentResultPage from "@/app/[country]/[locale]/(checkout)/payment-result/[id]/page";

const getOrderMock = vi.fn();
const getSessionMock = vi.fn();
const getCombinationMock = vi.fn();
const isAuthenticatedMock = vi.fn();

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

// 客户端子组件（ShippingGroups / AddressBlock）走 useTranslations，同样返回 key
vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

vi.mock("@/lib/data/order-payment", () => ({
  getOrderForCheckout: (...args: unknown[]) => getOrderMock(...args),
  getOrderPaymentSession: (...args: unknown[]) => getSessionMock(...args),
}));

vi.mock("@/lib/data/payment-combination", () => ({
  getPaymentCombination: (...args: unknown[]) => getCombinationMock(...args),
}));

vi.mock("@/lib/data/cookies", () => ({
  isAuthenticated: (...args: unknown[]) => isAuthenticatedMock(...args),
}));

const order = {
  id: "or_1",
  number: "R1",
  state: "pending",
  payment_status: "balance_due",
  display_total: "$10.00",
} as Order;

/** 含履约信息的订单夹具（B3：Ship to / Delivery / Items / Paid / savings）。 */
const orderWithFulfillment = {
  ...order,
  payment_status: "paid",
  total: "55.00",
  display_total: "$55.00",
  discount_total: "-20.00",
  display_discount_total: "-$20.00",
  currency: "USD",
  items: [
    { id: "li_1", name: "Product A", quantity: 1, display_total: "$35.00" },
    { id: "li_2", name: "Product B", quantity: 2, display_total: "$40.00" },
  ],
  fulfillments: [
    {
      id: "ful_1",
      number: "H1",
      display_cost: "$5.00",
      delivery_method: { name: "Standard Shipping" },
      items: [{ item_id: "li_1", variant_id: "var_1", quantity: 1 }],
    },
  ],
  shipping_address: {
    full_name: "Jane Doe",
    address1: "1 Main St",
    city: "Springfield",
    zipcode: "12345",
    country_name: "United States",
  },
} as unknown as Order;

function renderResult(id = "or_1", session = "ps_1", notice?: string) {
  return PaymentResultPage({
    params: Promise.resolve({ id, country: "us", locale: "en" }),
    searchParams: Promise.resolve({ session, ...(notice ? { notice } : {}) }),
  }).then((view) => render(view));
}

describe("PaymentResultPage (PRD-20260830-checkout AC-009)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    isAuthenticatedMock.mockResolvedValue(false);
    getOrderMock.mockResolvedValue(order);
    getSessionMock.mockResolvedValue({
      id: "ps_1",
      status: "pending",
    } as PaymentSession);
  });

  it("uses the authoritative paid Order state for success", async () => {
    getOrderMock.mockResolvedValue({ ...order, payment_status: "paid" });

    await renderResult();

    expect(screen.getByRole("heading", { name: "successTitle" })).toBeTruthy();
    expect(screen.queryByText("retryPayment")).toBeNull();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-003
  it("shows failure and retries the same Order", async () => {
    getSessionMock.mockResolvedValue({ id: "ps_1", status: "failed" });

    await renderResult();

    expect(screen.getByRole("heading", { name: "failedTitle" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "retryPayment" })).toHaveAttribute(
      "href",
      "/us/en/checkout/or_1",
    );
  });

  it("shows canceled state from the server session", async () => {
    getSessionMock.mockResolvedValue({ id: "ps_1", status: "canceled" });

    await renderResult();

    expect(screen.getByRole("heading", { name: "canceledTitle" })).toBeTruthy();
  });

  it("shows a pending combination and refreshes the same target", async () => {
    getCombinationMock.mockResolvedValue({
      success: true,
      id: "pcom_1",
      status: "pending",
      amount: "30.00",
      currency: "USD",
    });

    await renderResult("pcom_1", "ps_combo");

    expect(screen.getByRole("heading", { name: "pendingTitle" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "refreshStatus" })).toHaveAttribute(
      "href",
      "/us/en/payment-result/pcom_1?session=ps_combo",
    );
  });

  // ── PRD-20260913-checkout-txn-error-routing AC-005/AC-006：恢复/处理中 notice ──
  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-002
  it("forces the recovery notice and hides retry actions when ?notice=recovery (AC-005)", async () => {
    getOrderMock.mockResolvedValue({ ...order, payment_status: "paid" });

    await renderResult("or_1", "ps_1", "recovery");

    expect(screen.getByRole("heading", { name: "recoveryTitle" })).toBeTruthy();
    expect(screen.getByText("recoveryDescription")).toBeTruthy();
    expect(screen.queryByText("retryPayment")).toBeNull();
    expect(screen.queryByText("refreshStatus")).toBeNull();
  });

  it("forces the processing notice and hides retry actions when ?notice=processing (AC-006)", async () => {
    await renderResult("or_1", "ps_1", "processing");

    expect(
      screen.getByRole("heading", { name: "processingNoticeTitle" }),
    ).toBeTruthy();
    expect(screen.getByText("processingNoticeDescription")).toBeTruthy();
    expect(screen.queryByText("retryPayment")).toBeNull();
    expect(screen.queryByText("refreshStatus")).toBeNull();
  });

  // ── PRD-20260915-checkout-…-b3-…：履约结果页（方案 §37） ──

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-004
  it("renders the fulfillment summary for a confirmed order (AC-004)", async () => {
    getOrderMock.mockResolvedValue(orderWithFulfillment);

    await renderResult("or_1", undefined);

    expect(screen.getByTestId("order-summary")).toBeTruthy();
    expect(screen.getByText("shipTo")).toBeTruthy();
    expect(screen.getByText("delivery")).toBeTruthy();
    expect(screen.getByText("items")).toBeTruthy();
    expect(screen.getByText("paid")).toBeTruthy();
    expect(screen.getByText("promotionSavings")).toBeTruthy();
    expect(screen.getByTestId("view-order-link")).toHaveAttribute(
      "href",
      "/us/en/order-placed/or_1",
    );
    // 成功态不额外渲染「订单内容」副标题（h1 已是 Order confirmed）
    expect(screen.queryByTestId("order-summary-heading")).toBeNull();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-004
  it("omits the savings row when there is no discount (AC-004)", async () => {
    getOrderMock.mockResolvedValue({
      ...orderWithFulfillment,
      discount_total: "0.0",
      display_discount_total: "$0.00",
    });

    await renderResult("or_1", undefined);

    expect(screen.queryByTestId("order-summary-savings")).toBeNull();
    expect(screen.getByTestId("order-summary-paid")).toBeTruthy();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-004
  it("keeps the summary on non-success states under an order-contents heading (AC-004)", async () => {
    // 支付状态未确认 + 会话失败 → failed（订单自身 paid 时状态优先为 success）
    getOrderMock.mockResolvedValue({
      ...orderWithFulfillment,
      payment_status: "balance_due",
      state: "pending",
    });
    getSessionMock.mockResolvedValue({ id: "ps_1", status: "failed" });

    await renderResult("or_1", "ps_1");

    expect(screen.getByRole("heading", { name: "failedTitle" })).toBeTruthy();
    expect(screen.getByTestId("order-summary-heading").textContent).toBe(
      "orderContents",
    );
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-005
  it("groups items per shipment when there are several fulfillments (AC-005)", async () => {
    getOrderMock.mockResolvedValue({
      ...orderWithFulfillment,
      fulfillments: [
        {
          id: "ful_1",
          display_cost: "$5.00",
          delivery_method: { name: "Standard Shipping" },
          items: [{ item_id: "li_1", variant_id: "var_1", quantity: 1 }],
        },
        {
          id: "ful_2",
          display_cost: "$0.00",
          delivery_method: { name: "Free Shipping" },
          items: [{ item_id: "li_2", variant_id: "var_2", quantity: 2 }],
        },
      ],
    });

    await renderResult("or_1", undefined);

    expect(screen.getAllByTestId("shipping-group")).toHaveLength(2);
    expect(screen.getAllByTestId("shipping-group-title")).toHaveLength(2);
    // 商品行同时在「订单内容」列表与配送分组里出现 → 查询限定在配送区内
    const delivery = within(screen.getByTestId("order-summary-delivery"));
    expect(delivery.getByText(/Product A/)).toBeTruthy();
    expect(delivery.getByText(/Product B/)).toBeTruthy();
    expect(delivery.getByText(/Standard Shipping/)).toBeTruthy();
    expect(delivery.getByText(/Free Shipping/)).toBeTruthy();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-005
  it("renders a single un-titled delivery row for one fulfillment (AC-005)", async () => {
    getOrderMock.mockResolvedValue(orderWithFulfillment);

    await renderResult("or_1", undefined);

    expect(screen.getAllByTestId("shipping-group")).toHaveLength(1);
    expect(screen.queryByTestId("shipping-group-title")).toBeNull();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-006
  it("never renders the payment session identifier (AC-006)", async () => {
    getOrderMock.mockResolvedValue(orderWithFulfillment);

    await renderResult("or_1", "ps_secret_1");

    expect(document.body.innerHTML).not.toContain("ps_secret_1");
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-009
  it("still renders the summary without fulfillments (AC-009)", async () => {
    getOrderMock.mockResolvedValue({
      ...orderWithFulfillment,
      fulfillments: [],
    });

    await renderResult("or_1", undefined);

    expect(screen.getByTestId("order-summary")).toBeTruthy();
    expect(screen.queryByTestId("order-summary-delivery")).toBeNull();
    expect(screen.getByTestId("order-summary-paid")).toBeTruthy();
  });
});
