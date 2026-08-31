import type { Order } from "@pallastrade/sdk";
import { render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { OrderPaymentContent } from "@/components/checkout/OrderPaymentContent";

const pushMock = vi.fn();
const replaceMock = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, replace: replaceMock }),
  usePathname: () => "/us/en/checkout/or_1",
  useSearchParams: () => ({ get: () => null }),
}));

const createOrderSessionMock = vi.fn();
const completeOrderSessionMock = vi.fn();
const completeOrderMock = vi.fn();

vi.mock("@/lib/data/order-payment", () => ({
  createOrderPaymentSession: (...args: unknown[]) =>
    createOrderSessionMock(...args),
  completeOrderPaymentSession: (...args: unknown[]) =>
    completeOrderSessionMock(...args),
  completeOrder: (...args: unknown[]) => completeOrderMock(...args),
}));

vi.mock("@/components/checkout/StripePaymentForm", () => ({
  StripePaymentForm: ({
    clientSecret,
    onReady,
  }: {
    clientSecret: string;
    onReady: (h: {
      confirmPayment: (url: string) => Promise<{ error?: string }>;
    }) => void;
  }) => {
    onReady({ confirmPayment: () => Promise.resolve({}) });
    return <div data-testid="stripe-form" data-secret={clientSecret} />;
  },
}));

const stripeMethod = {
  id: "pm_stripe",
  name: "Stripe",
  type: "stripe",
  session_required: true,
};

const checkMethod = {
  id: "pm_check",
  name: "Check",
  type: "check",
  session_required: false,
};

const order = {
  id: "or_1",
  number: "R123456",
  state: "pending",
  payment_methods: [stripeMethod, checkMethod],
  shipping_address: {
    first_name: "Ada",
    last_name: "Lovelace",
    address1: "1 Main St",
    city: "New York",
    state_abbr: "NY",
    postal_code: "10001",
    country_iso: "US",
    phone: "555-555-0199",
  },
  items: [
    {
      id: "line_1",
      name: "Test Product",
      quantity: 1,
      thumbnail_url: null,
      display_total: "$10.00",
      display_item_total: "$10.00",
    },
  ],
  display_total: "$10.00",
  display_item_total: "$10.00",
  display_delivery_total: "0",
  display_amount_due: "$10.00",
} as unknown as Order;

describe("OrderPaymentContent", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // 默认：自动创建 session 返回失败（避免未设置时 undefined.success 报错）
    createOrderSessionMock.mockResolvedValue({
      success: false,
      error: "no session",
    });
  });

  it("renders shipping address, payment methods and order summary", () => {
    render(<OrderPaymentContent order={order} />);

    expect(screen.getByText("shippingAddress")).toBeTruthy();
    expect(screen.getByText("paymentMethod")).toBeTruthy();
    expect(screen.getByText("orderSummary")).toBeTruthy();
    expect(screen.getByText("Ada Lovelace")).toBeTruthy();
  });

  it("automatically creates a Stripe payment session and shows the card form when Stripe is selected", async () => {
    createOrderSessionMock.mockResolvedValue({
      success: true,
      session: {
        id: "ps_1",
        external_data: { client_secret: "cs_test_abc_secret_xyz%2Fsegment" },
      },
    });

    render(<OrderPaymentContent order={order} />);

    await waitFor(() => {
      expect(createOrderSessionMock).toHaveBeenCalledWith("or_1", "pm_stripe");
    });

    const form = await screen.findByTestId("stripe-form");
    expect(form).toBeTruthy();
    // client_secret 解码后传给 StripePaymentForm
    expect(form.getAttribute("data-secret")).toBe(
      "cs_test_abc_secret_xyz/segment",
    );
  });

  it("keeps the pay-now button flow for non-session methods (Check)", async () => {
    const checkOnlyOrder = {
      ...order,
      payment_methods: [checkMethod],
    } as unknown as Order;

    render(<OrderPaymentContent order={checkOnlyOrder} />);

    // Check 非 session：不自动创建 session
    expect(createOrderSessionMock).not.toHaveBeenCalled();
    // 仍显示支付方式 + Pay 按钮（走 handlePay 线下收款跳转）
    expect(screen.getByText("Check")).toBeTruthy();
  });
});
