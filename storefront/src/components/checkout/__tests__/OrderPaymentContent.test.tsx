import type { CheckoutView, Country, Order } from "@pallastrade/sdk";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { OrderPaymentContent } from "@/components/checkout/OrderPaymentContent";
import { CheckoutProvider, CheckoutSummary } from "@/contexts/CheckoutContext";

const getOrderCheckoutMock = vi.fn();
const updateOrderCheckoutMock = vi.fn();
vi.mock("@/lib/data/order-checkout", () => ({
  getOrderCheckout: (...args: unknown[]) => getOrderCheckoutMock(...args),
  updateOrderCheckout: (...args: unknown[]) => updateOrderCheckoutMock(...args),
}));
vi.mock("@/lib/data/countries", () => ({
  getCountry: async () => ({ states: [] }),
}));

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
const completeAndRedirectMock = vi.fn();

vi.mock("@/lib/data/order-payment", () => ({
  createOrderPaymentSession: (...args: unknown[]) =>
    createOrderSessionMock(...args),
  completeOrderPaymentSession: (...args: unknown[]) =>
    completeOrderSessionMock(...args),
  completeOrderPaymentSessionAndRedirectToResult: (...args: unknown[]) =>
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

// CHK-P1-4: server CheckoutView projection (view 缺失时组件回退 order 快照)。
const checkoutView = {
  id: "or_1",
  number: "R123456",
  state: "pending",
  payment_state: "balance_due",
  email: "ada@example.com",
  currency: "USD",
  version: 2,
  price_version: "abc123def4567890",
  expires_at: null,
  ready: true,
  missing_requirements: [],
  items: [
    {
      id: "line_1",
      name: "Test Product",
      quantity: 1,
      thumbnail_url: null,
      display_total: "$10.00",
    },
  ],
  display_item_total: "$10.00",
  display_delivery_total: "0",
  display_tax_total: null,
  display_total: "$10.00",
  display_amount_due: "$10.00",
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
  billing_address: null,
  discounts: [],
  taxes: [],
  fulfillments: [
    {
      id: "ship_1",
      delivery_rates: [
        {
          id: "dr_standard",
          name: "Standard",
          selected: true,
          cost: "0",
          total: "0",
          display_cost: "$0.00",
        },
        {
          id: "dr_fast",
          name: "Express",
          selected: false,
          cost: "9.99",
          total: "9.99",
          display_cost: "$9.99",
        },
      ],
    },
  ],
} as unknown as CheckoutView;

const countries = [
  { iso: "US", name: "United States" },
] as unknown as Country[];

function renderOrderPayment(
  targetOrder: Order = order,
  view?: CheckoutView | null,
  targetCountries?: Country[],
) {
  return render(
    <CheckoutProvider>
      <OrderPaymentContent
        order={targetOrder}
        view={view}
        countries={targetCountries}
      />
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
    getOrderCheckoutMock.mockResolvedValue(null);
    updateOrderCheckoutMock.mockResolvedValue({
      success: true,
      view: checkoutView,
    });
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

  // CHK-P1-4 (AC-403): 金额/商品以服务端 CheckoutView 投影为准。
  it("renders summary money from the CheckoutView projection when provided", () => {
    const differentView = {
      ...checkoutView,
      display_total: "$25.00",
      display_item_total: "$25.00",
    } as unknown as CheckoutView;

    renderOrderPayment(order, differentView);

    expect(screen.getByTestId("order-payment-summary")).toBeInTheDocument();
    // 金额行（小计/总计）取投影值 $25.00；行项目单价仍为 $10.00（投影 items）。
    expect(screen.getAllByText("$25.00").length).toBeGreaterThan(0);
    expect(screen.getAllByText("$10.00").length).toBeGreaterThan(0);
  });

  // CHK-P1-4 (AC-403): ready=false → Pay 禁用 + missing_requirements 提示可见。
  it("disables Pay and shows the readiness notice when view.ready is false", () => {
    const notReadyView = {
      ...checkoutView,
      ready: false,
      missing_requirements: ["contact", "shipping_address"],
    } as unknown as CheckoutView;

    renderOrderPayment(order, notReadyView);

    const notice = screen.getByTestId("checkout-not-ready");
    expect(notice).toBeInTheDocument();
    expect(notice.getAttribute("data-missing")).toBe(
      "contact,shipping_address",
    );
    expect(
      (screen.getByRole("button", { name: "payAmount" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
  });

  // CHK-P1-4: Pay 点击在 !ready 时不创建会话（前端门控 + toast 提示）。
  it("does not create a session when Pay is clicked while not ready", async () => {
    const user = userEvent.setup();
    const notReadyView = {
      ...checkoutView,
      ready: false,
      missing_requirements: ["contact"],
    } as unknown as CheckoutView;

    renderOrderPayment(order, notReadyView);

    const pay = screen.getByRole("button", {
      name: "payAmount",
    }) as HTMLButtonElement;
    // 禁用态下 userEvent 不触发 onClick；直接断言未创建会话。
    expect(pay.disabled).toBe(true);
    await user.click(screen.getByTestId("checkout-not-ready"));
    expect(createOrderSessionMock).not.toHaveBeenCalled();
  });

  // CHK-P1-4B (AC-604): 物流 rate 编辑 → PATCH delivery_rate_id。
  it("saves a delivery-rate change through updateOrderCheckout", async () => {
    const user = userEvent.setup();
    renderOrderPayment(order, checkoutView);

    await user.click(screen.getByTestId("edit-delivery"));
    expect(screen.getByTestId("delivery-editor")).toBeInTheDocument();

    await user.click(screen.getByTestId("rate-dr_fast"));
    await user.click(screen.getByTestId("save-delivery"));

    await waitFor(() =>
      expect(updateOrderCheckoutMock).toHaveBeenCalledWith("or_1", {
        delivery_rate_id: "dr_fast",
      }),
    );
  });

  // CHK-P1-4B (AC-603): 地址编辑（countries 提供时）→ PATCH shipping_address。
  it("opens the address editor and saves through updateOrderCheckout", async () => {
    const user = userEvent.setup();
    renderOrderPayment(order, checkoutView, countries);

    await user.click(screen.getByTestId("edit-address"));
    expect(screen.getByTestId("address-editor")).toBeInTheDocument();

    await user.click(screen.getByTestId("save-address"));

    await waitFor(() => {
      expect(updateOrderCheckoutMock).toHaveBeenCalled();
      const [, params] = updateOrderCheckoutMock.mock.calls[0];
      expect(params.shipping_address.country_iso).toBe("US");
    });
  });

  // CHK-P1-4B (AC-605): 会话创建返回 checkout_version_conflict → 提示 + 重取 view（不支付）。
  it("refreshes the view on a checkout_version_conflict session error without paying", async () => {
    const user = userEvent.setup();
    createOrderSessionMock.mockResolvedValue({
      success: false,
      code: "checkout_version_conflict",
      error: "quote changed",
    });

    renderOrderPayment(order, checkoutView);

    await user.click(screen.getByRole("button", { name: "payAmount" }));

    await waitFor(() =>
      expect(getOrderCheckoutMock).toHaveBeenCalledWith("or_1"),
    );
    expect(completeAndRedirectMock).not.toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
  });

  // TXN-P2-6 轮3 (AC-5): transactions.create 的 quote_changed（409）与既有
  // checkout_version_conflict 同语义 → 提示 + 重取 view（不自动支付，INV-07）。
  it("refreshes the view on a quote_changed transaction error without paying", async () => {
    const user = userEvent.setup();
    createOrderSessionMock.mockResolvedValue({
      success: false,
      code: "quote_changed",
      error: "quote changed",
    });

    renderOrderPayment(order, checkoutView);

    await user.click(screen.getByRole("button", { name: "payAmount" }));

    await waitFor(() =>
      expect(getOrderCheckoutMock).toHaveBeenCalledWith("or_1"),
    );
    expect(completeAndRedirectMock).not.toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
  });
});
