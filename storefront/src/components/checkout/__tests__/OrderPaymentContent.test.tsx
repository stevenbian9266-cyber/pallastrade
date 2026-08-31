import type { Order } from "@pallastrade/sdk";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { OrderPaymentContent } from "@/components/checkout/OrderPaymentContent";
import { CheckoutProvider, CheckoutSummary } from "@/contexts/CheckoutContext";

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
const completeAndRedirectMock = vi.fn();

vi.mock("@/lib/data/order-payment", () => ({
  createOrderPaymentSession: (...args: unknown[]) =>
    createOrderSessionMock(...args),
  completeOrderPaymentSession: (...args: unknown[]) =>
    completeOrderSessionMock(...args),
  completeOrder: (...args: unknown[]) => completeOrderMock(...args),
  completeOrderAndRedirectToOrderPlaced: (...args: unknown[]) =>
    completeAndRedirectMock(...args),
}));

vi.mock("@/lib/utils/stripe", () => ({
  stripePromise: Promise.resolve(null),
  normalizeClientSecret: (s: string) => s,
  extractSessionClientSecret: (
    session: {
      external_data?: Record<string, unknown> | null;
    } | null,
  ) => {
    const raw = session?.external_data?.client_secret as string | undefined;
    return raw ? decodeURIComponent(raw) : null;
  },
}));

const confirmMock = vi.fn();
const validateMock = vi.fn().mockReturnValue(true);
vi.mock("@/components/checkout/CardPaymentForm", () => ({
  CardPaymentForm: ({
    onReady,
  }: {
    onReady: (h: {
      confirmPayment: (secret: string) => Promise<{ error?: string }>;
      validate: () => boolean;
    }) => void;
  }) => {
    onReady({
      confirmPayment: (secret: string) => confirmMock(secret),
      validate: () => validateMock(),
    });
    return <div data-testid="card-payment-form" />;
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

function renderOrderPayment(targetOrder: Order = order) {
  return render(
    <CheckoutProvider>
      <OrderPaymentContent order={targetOrder} />
      <CheckoutSummary />
    </CheckoutProvider>,
  );
}

describe("OrderPaymentContent", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    confirmMock.mockResolvedValue({});
    createOrderSessionMock.mockResolvedValue({
      success: true,
      session: {
        id: "ps_1",
        external_data: { client_secret: "pi_test_abc_secret_xyz%2Fsegment" },
      },
    });
    completeOrderSessionMock.mockResolvedValue({ success: true });
    completeOrderMock.mockResolvedValue({ success: true, order: {} });
  });

  it("renders shipping address, payment methods and order summary", () => {
    renderOrderPayment();

    expect(screen.getByText("shippingAddress")).toBeTruthy();
    expect(screen.getByText("paymentMethod")).toBeTruthy();
    expect(screen.getByText("orderSummary")).toBeTruthy();
    expect(screen.getByTestId("order-payment-summary")).toBeInTheDocument();
    expect(screen.getByText("Ada Lovelace")).toBeTruthy();
  });

  it("renders the self-drawn card form immediately when Stripe is selected (no client_secret needed)", () => {
    renderOrderPayment();

    // PRD-20260831-payments-stripe-自绘卡支付表单：表单始终渲染，不预创建会话
    expect(screen.getByTestId("card-payment-form")).toBeInTheDocument();
    expect(createOrderSessionMock).not.toHaveBeenCalled();
  });

  it("creates a PaymentIntent session and confirms payment on Pay Now (Stripe)", async () => {
    const user = userEvent.setup();
    renderOrderPayment();

    // 表单已渲染
    expect(screen.getByTestId("card-payment-form")).toBeInTheDocument();

    // 点 Pay → 创建 PaymentIntent 会话 → confirmCardPayment
    await user.click(screen.getByRole("button", { name: "payAmount" }));
    await waitFor(() =>
      expect(createOrderSessionMock).toHaveBeenCalledWith(
        "or_1",
        "pm_stripe",
        undefined,
        "payment_intent",
      ),
    );
    await waitFor(() =>
      expect(confirmMock).toHaveBeenCalledWith(
        "pi_test_abc_secret_xyz/segment",
      ),
    );

    // 完成会话 + 完成订单 → server action 内 redirect（确定性导航）
    await waitFor(() =>
      expect(completeAndRedirectMock).toHaveBeenCalledWith(
        "or_1",
        "ps_1",
        "/us/en",
      ),
    );
    expect(pushMock).not.toHaveBeenCalled();
  });

  it("keeps the pay-now button flow for non-session methods (Check)", async () => {
    const checkOnlyOrder = {
      ...order,
      payment_methods: [checkMethod],
    } as unknown as Order;

    renderOrderPayment(checkOnlyOrder);

    // Check 非 session：无自绘卡表单、不创建 session
    expect(screen.queryByTestId("card-payment-form")).not.toBeInTheDocument();
    expect(createOrderSessionMock).not.toHaveBeenCalled();
    // 仍显示支付方式 + Pay 按钮（走 handlePay 线下收款跳转）
    expect(screen.getByText("Check")).toBeTruthy();
  });
});
