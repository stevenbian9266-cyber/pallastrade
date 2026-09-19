import type { CheckoutView, Country, Order } from "@pallastrade/sdk";
import { act, render, screen, waitFor, within } from "@testing-library/react";
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

// PRD-20260913-checkout-txn-error-routing AC-007：notice 参数可控（vi.hoisted 供 mock 工厂读取）。
const searchParamsState = vi.hoisted(() => ({ notice: null as string | null }));

/** D7 补口 2：钱包可用性分支需要「已配置 Stripe」的环境。 */
const stripeConfiguredState = vi.hoisted(() => ({ value: false }));

/** 捕获 ExpressCheckoutElement 的 props（用于驱动 onReady 上报设备钱包能力）。 */
let capturedExpressProps: Record<string, unknown> = {};
vi.mock("@stripe/react-stripe-js", () => ({
  Elements: ({ children }: { children: React.ReactNode }) => children,
  ExpressCheckoutElement: (props: Record<string, unknown>) => {
    capturedExpressProps = props;
    return <div data-testid="express-checkout-element" />;
  },
  useStripe: () => ({ confirmPayment: vi.fn() }),
  useElements: () => ({ submit: vi.fn().mockResolvedValue({}) }),
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
  useLocale: () => "en",
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, replace: replaceMock }),
  usePathname: () => "/us/en/checkout/or_1",
  useSearchParams: () => ({
    get: (key: string) => (key === "notice" ? searchParamsState.notice : null),
  }),
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
  getStripePromise: () => Promise.resolve(null),
  isStripeConfigured: () => stripeConfiguredState.value,
  resolveStripePublishableKey: () => null,
  stripeLocaleFor: (locale: string) => locale,
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
  // D7（PRD-20260918-payments-d7-payment-section-express）：服务端下发入口级列表
  entries: [
    {
      option_id: "pm_stripe:card",
      method_key: "card",
      display_name: "Credit Card",
      frontend_kind: "inline",
      group: "card",
      position: 1,
    },
    {
      option_id: "pm_stripe:apple_pay",
      method_key: "apple_pay",
      display_name: "Apple Pay",
      frontend_kind: "express",
      group: "wallet",
      position: 2,
    },
  ],
};

const checkMethod = {
  id: "pm_check",
  name: "Check",
  type: "check",
  session_required: false,
  entries: [
    {
      option_id: "pm_check:check",
      method_key: "check",
      display_name: "Check",
      frontend_kind: "manual",
      group: "manual",
      position: 1,
    },
  ],
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
  preflight?: Record<string, unknown> | null,
) {
  return render(
    <CheckoutProvider>
      <OrderPaymentContent
        order={targetOrder}
        view={view}
        countries={targetCountries}
        preflight={
          (preflight ?? null) as unknown as import("@pallastrade/sdk").StoreOrdersPaymentPreflight | null
        }
      />
      <CheckoutSummary />
    </CheckoutProvider>,
  );
}

// PRD-20260919-checkout-结算页待支付订单再次支付重验-失效行剔除-优惠复核-订单金额变化提示-收银台弹窗退役 AC-008 / AC-009
describe("OrderPaymentContent preflight (PRD-20260919-checkout)", () => {
  const basePreflight = {
    id: "or_1",
    payable: true,
    order_id: "or_1",
    number: "R123456",
    blockers: [] as Array<Record<string, unknown>>,
    changes: [] as Array<Record<string, unknown>>,
    invalid_items: [] as Array<Record<string, unknown>>,
    quote: {
      checkout_version: 3,
      price_version: "abc",
      expires_at: null,
      amount_due: "90.00",
      display_amount_due: "$90.00",
      total: "90.00",
      display_total: "$90.00",
    },
    amount_due_before: "100.00",
    amount_due_after: "90.00",
    display_amount_due_before: "$100.00",
    display_amount_due_after: "$90.00",
    total_before: "100.00",
    total_after: "90.00",
    display_total_before: "$100.00",
    display_total_after: "$90.00",
    window: { valid: true, expires_at: null, window_minutes: 30, reissued: false },
  };

  it("AC-008: 金额变化时直接回显新金额并显示提示（无二次确认动作）", () => {
    renderOrderPayment(order, checkoutView, countries, basePreflight);

    const notice = screen.getByTestId("order-amount-updated-notice");
    expect(notice).toBeInTheDocument();
    // i18n mock 返回 key：金额变化标题 key 可见
    expect(
      within(notice).getByTestId("order-amount-updated-title"),
    ).toBeInTheDocument();
    // 摘要直接显示重验后金额（不强加确认步骤，Pay 仍可直接点）
    expect(screen.getByTestId("pay-now-button")).toBeEnabled();
  });

  it("AC-008: 失效商品被列出（只对有效商品扣款）", () => {
    renderOrderPayment(order, checkoutView, countries, {
      ...basePreflight,
      invalid_items: [
        {
          line_item_id: "li_gone",
          variant_id: "var_gone",
          name: "Rotary Shaver 5000",
          sku: "RS-5000",
          quantity: 1,
          amount: "100.00",
          reason: "archived",
        },
      ],
      changes: [
        { kind: "item_removed", subject: "item_removed", name: "Rotary Shaver 5000" },
      ],
    });

    const invalidNotice = screen.getByTestId("invalid-items-notice");
    expect(invalidNotice).toBeInTheDocument();
    // i18n mock 只回 key（不插值）→ 断言列表条目数与 key 文案
    expect(within(invalidNotice).getAllByRole("listitem")).toHaveLength(1);
    expect(
      within(invalidNotice).getByText("invalidItemRow"),
    ).toBeInTheDocument();
    expect(
      within(invalidNotice).getByText("payableItemsHint"),
    ).toBeInTheDocument();
  });

  it("AC-009: 硬阻断（配送不可达）→ Pay 禁用 + 原因可见", () => {
    renderOrderPayment(order, checkoutView, countries, {
      ...basePreflight,
      payable: false,
      blockers: [
        {
          code: "delivery_unavailable",
          message: "Some items cannot be shipped to the current destination",
          missing_requirements: [],
          items: [],
        },
      ],
    });

    expect(screen.getByTestId("revalidation-blocked-notice")).toBeInTheDocument();
    expect(screen.getByTestId("pay-now-button")).toBeDisabled();
  });

  it("无变化时不渲染提示块", () => {
    renderOrderPayment(order, checkoutView, countries, {
      ...basePreflight,
      amount_due_before: "90.00",
      display_amount_due_before: "$90.00",
      total_before: "90.00",
      display_total_before: "$90.00",
    });

    expect(
      screen.queryByTestId("order-amount-updated-notice"),
    ).not.toBeInTheDocument();
  });
});

describe("OrderPaymentContent", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    searchParamsState.notice = null;
    stripeConfiguredState.value = false;
    capturedExpressProps = {};
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

  // PRD-20260913-checkout-billing-mode AC-012：`or_` 支付页不涉账单分支，本文件用例为回归基线
  it("renders shipping address, payment methods and order summary", () => {
    renderOrderPayment();

    expect(screen.getByText("shippingAddress")).toBeTruthy();
    expect(screen.getByText("paymentMethod")).toBeTruthy();
    expect(screen.getByText("orderSummary")).toBeTruthy();
    expect(screen.getByTestId("order-payment-summary")).toBeInTheDocument();
    expect(screen.getByText("Ada Lovelace")).toBeTruthy();
  });

  // ── PRD-20260913-checkout-txn-error-routing AC-007：报价变化横幅 ──
  it("shows the quote-updated banner when ?notice=quote_changed (AC-007)", () => {
    searchParamsState.notice = "quote_changed";

    renderOrderPayment();

    expect(screen.getByTestId("quote-updated-banner")).toBeInTheDocument();
    expect(screen.getByText("quoteUpdatedBanner")).toBeTruthy();
  });

  it("does not show the quote-updated banner without the notice param (AC-007)", () => {
    renderOrderPayment();

    expect(screen.queryByTestId("quote-updated-banner")).toBeNull();
  });

  // ── PRD-20260913-checkout-money-contract AC-001/AC-002：raw 判逻辑 / display 仅渲染 ──
  it("renders shipping and tax rows from raw amounts even when display strings carry symbols (AC-001/AC-002)", () => {
    const viewWithCharges = {
      ...checkoutView,
      delivery_total: "8.00",
      tax_total: "5.00",
      display_delivery_total: "$8.00",
      display_tax_total: "$5.00",
    } as unknown as CheckoutView;

    renderOrderPayment(order, viewWithCharges);

    expect(screen.getByText("shipping")).toBeTruthy();
    expect(screen.getByText("$8.00")).toBeTruthy();
    expect(screen.getByText("tax")).toBeTruthy();
    expect(screen.getByText("$5.00")).toBeTruthy();
  });

  it("hides the shipping row when the raw delivery total is zero (AC-002 boundary)", () => {
    const viewWithoutShipping = {
      ...checkoutView,
      delivery_total: "0.0",
      tax_total: null,
      display_delivery_total: "$0.00",
      display_tax_total: null,
    } as unknown as CheckoutView;

    renderOrderPayment(order, viewWithoutShipping);

    expect(screen.queryByText("$0.00")).toBeNull();
    expect(screen.queryByText("shipping")).toBeNull();
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
    await user.click(screen.getByTestId("pay-now-button"));
    await waitFor(() =>
      expect(createOrderSessionMock).toHaveBeenCalledWith(
        "or_1",
        "pm_stripe",
        undefined,
        "payment_intent",
        // D7 FR-005：入口（method kind）随请求下发做同源校验
        { optionKind: "card" },
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

  // ── D7（PRD-20260918-payments-d7-payment-section-express）─────────────────
  // PRD-20260918-payments-d7-payment-section-express AC-006：入口级列表 —— 一入口一行（顺序 = 服务端 position），形态来自 frontend_kind
  it("renders one row per server-projected entry in position order (D7 AC-006)", () => {
    renderOrderPayment();

    const rows = screen.getAllByTestId("payment-entry-row");
    expect(rows.map((row) => row.getAttribute("data-option-id"))).toEqual([
      "pm_stripe:card",
      "pm_stripe:apple_pay",
      "pm_check:check",
    ]);
    expect(rows[1].getAttribute("data-frontend-kind")).toBe("express");
    expect(screen.getByText("Apple Pay")).toBeTruthy();
  });

  // PRD-20260918-payments-d7-payment-section-express AC-007：选中钱包入口 → 创建会话前不渲染卡表单；钱包按钮就位
  it("renders the wallet entry as a wallet button instead of the card form (D7 AC-007)", async () => {
    const user = userEvent.setup();
    renderOrderPayment();

    await user.click(screen.getByText("Apple Pay"));

    // 卡表单只在 inline 入口选中时渲染
    expect(screen.queryByTestId("card-payment-form")).not.toBeInTheDocument();
    // 未配置 Stripe 的测试环境 → 钱包组件不渲染具体按钮，但也不得回落卡表单
    expect(createOrderSessionMock).not.toHaveBeenCalled();
  });

  // PRD-20260918-payments-d7-payment-section-express AC-010：旧响应（无 entries）→ 回落「一 provider 一行」（display_name ?? name）
  it("falls back to one row per provider when the projection has no entries (D7 AC-010)", () => {
    const legacyOrder = {
      ...order,
      payment_methods: [{ ...checkMethod, entries: undefined }],
    } as unknown as Order;

    renderOrderPayment(legacyOrder);

    const rows = screen.getAllByTestId("payment-entry-row");
    expect(rows).toHaveLength(1);
    expect(rows[0].getAttribute("data-option-id")).toBe("pm_check:default");
    expect(screen.getByText("Check")).toBeTruthy();
  });

  // PRD-20260918-payments-d7-payment-section-express AC-009：移动端吸底 Pay 条 —— 与页内 Pay 同一 handler（同一 session 创建调用）
  it("exposes a mobile sticky pay bar wired to the same pay handler (D7 AC-009)", async () => {
    const user = userEvent.setup();
    renderOrderPayment();

    const bar = screen.getByTestId("mobile-pay-bar");
    expect(bar).toBeInTheDocument();
    expect(bar.textContent).toContain("$10.00");

    // 吸底条按钮与页内按钮同一 handler：点击同样走 session 创建 → 确认 → 完成
    const barButton = within(bar).getByRole("button");
    await user.click(barButton);

    await waitFor(() =>
      expect(createOrderSessionMock).toHaveBeenCalledWith(
        "or_1",
        "pm_stripe",
        undefined,
        "payment_intent",
        { optionKind: "card" },
      ),
    );
  });

  // PRD-20260918-payments-d7-payment-section-express AC-008：入口被服务端拒绝 → 刷新支付方式列表（不进入支付流程）
  it("refreshes the payment list when the server rejects the option kind (D7 AC-008)", async () => {
    const user = userEvent.setup();
    createOrderSessionMock.mockResolvedValueOnce({
      success: false,
      code: "payment_option_not_available",
      error: "Payment method is not available for this order",
    });
    renderOrderPayment();

    await user.click(screen.getByTestId("pay-now-button"));

    await waitFor(() => expect(getOrderCheckoutMock).toHaveBeenCalled());
  });

  // PRD-20260918-payments-d7-payment-section-express AC-011：
  // 本设备无该钱包（Stripe 报告全 false）→ 入口行置灰禁用 + 自动回落卡支付 + 显式说明，不再留空白。
  it("greys out the wallet entry and falls back to card when the device has no wallet (D7 AC-011)", async () => {
    const user = userEvent.setup();
    stripeConfiguredState.value = true;
    renderOrderPayment();

    // 选钱包入口 → 点钱包按钮（建会话）→ 挂载 ExpressCheckoutElement
    // （页内槽位 + 移动吸底条各一个钱包组件 → 取页内第一个）
    await user.click(screen.getByText("Apple Pay"));
    const walletButtons = await screen.findAllByTestId("wallet-pay-button");
    await user.click(walletButtons[0]);
    await screen.findAllByTestId("express-checkout-element");

    // 设备能力上报：无可用钱包
    await act(async () => {
      (capturedExpressProps.onReady as (event: unknown) => void)({
        availablePaymentMethods: {
          applePay: false,
          googlePay: false,
          link: false,
        },
      });
    });

    // ① 入口行标注原因（只标注，不删除服务端下发的入口集合）+ **保持可点击 = 重试**
    const walletRow = screen
      .getAllByTestId("payment-entry-row")
      .find((r) => r.getAttribute("data-option-id") === "pm_stripe:apple_pay");
    expect(walletRow?.getAttribute("data-unavailable")).toBe("device");
    const walletRadio = walletRow?.querySelector("input");
    expect((walletRadio as HTMLInputElement).disabled).toBe(false);
    expect(
      screen
        .getByTestId("payment-entry-unavailable")
        .getAttribute("data-reason"),
    ).toBe("device");

    // ② 自动回落卡支付：卡表单回来，钱包槽位不再留空白
    await waitFor(() =>
      expect(screen.getByTestId("card-payment-form")).toBeInTheDocument(),
    );
    expect(screen.queryByTestId("express-checkout-element")).toBeNull();

    // ③ 重新点该入口 = 重试：清除标注 + 重新挂载钱包组件重新探测（D7 AC-014）
    await user.click(screen.getByText("Apple Pay"));
    await screen.findAllByTestId("wallet-pay-button");
    expect(
      screen
        .getAllByTestId("payment-entry-row")
        .find((r) => r.getAttribute("data-option-id") === "pm_stripe:apple_pay")
        ?.getAttribute("data-unavailable"),
    ).toBeNull();
  });

  // PRD-20260916-payments-d16-payment-method-presentation AC-005：
  // 支付方法行优先渲染服务端下发的入口级展示名（display_name），缺失时回落 provider 名。
  // D7 后：入口级列表存在时以 `entries[].display_name` 为准；无 entries 的旧响应回落
  // provider 级 `display_name ?? name`（本用例即该回退路径）。
  it("renders the entry-level display name when the API provides one (D16 AC-005)", () => {
    const brandedMethod = {
      ...checkMethod,
      entries: undefined,
      display_name: "信用卡",
      method_key: "card",
    };
    const brandedOrder = {
      ...order,
      payment_methods: [brandedMethod],
    } as unknown as Order;

    renderOrderPayment(brandedOrder);

    expect(screen.getByText("信用卡")).toBeTruthy();
    expect(screen.queryByText("Check")).not.toBeInTheDocument();
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
      (screen.getByTestId("pay-now-button") as HTMLButtonElement).disabled,
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

    const pay = screen.getByTestId("pay-now-button") as HTMLButtonElement;
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

    await user.click(screen.getByTestId("pay-now-button"));

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

    await user.click(screen.getByTestId("pay-now-button"));

    await waitFor(() =>
      expect(getOrderCheckoutMock).toHaveBeenCalledWith("or_1"),
    );
    expect(completeAndRedirectMock).not.toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
  });

  // ── B1（PRD-20260914-checkout B1）：credits / capabilities / 视图支付方式 ──
  it("renders gift-card and store-credit rows from CheckoutView credits (AC-010)", () => {
    const creditsView = {
      ...checkoutView,
      credits: {
        gift_cards: [
          {
            id: "gc_1",
            code: "GIFT-1",
            amount: "3.0",
            display_amount: "$3.00",
          },
        ],
        store_credit: { amount: "2.0", display_amount: "$2.00" },
      },
    } as unknown as CheckoutView;

    renderOrderPayment(order, creditsView);

    expect(screen.getByTestId("gift-card-row")).toBeInTheDocument();
    expect(screen.getByTestId("store-credit-row")).toBeInTheDocument();
    expect(screen.getByText("-$3.00")).toBeTruthy();
    expect(screen.getByText("-$2.00")).toBeTruthy();
  });

  it("omits the credits rows when nothing is applied (AC-010 boundary)", () => {
    renderOrderPayment(order, checkoutView);

    expect(screen.queryByTestId("gift-card-row")).toBeNull();
    expect(screen.queryByTestId("store-credit-row")).toBeNull();
  });

  it("disables Pay when capabilities.can_pay is false (AC-011)", () => {
    const notPayableView = {
      ...checkoutView,
      capabilities: {
        can_edit_address: false,
        can_change_shipping: false,
        can_apply_promotion: false,
        can_pay: false,
      },
    } as unknown as CheckoutView;

    renderOrderPayment(order, notPayableView);

    const pay = screen.getByTestId("pay-now-button") as HTMLButtonElement;
    expect(pay.disabled).toBe(true);
  });

  it("renders payment methods from the CheckoutView when the order snapshot has none (AC-012)", () => {
    const orderWithoutMethods = {
      ...order,
      payment_methods: [],
    } as unknown as Order;
    const viewWithMethods = {
      ...checkoutView,
      payment: { available_payment_methods: [stripeMethod] },
    } as unknown as CheckoutView;

    renderOrderPayment(orderWithoutMethods, viewWithMethods);

    expect(screen.getByText("Credit Card")).toBeTruthy();
    expect(screen.getByTestId("card-payment-form")).toBeInTheDocument();
  });

  // FR-006：编辑入口按 capabilities 控制（不可编辑时禁用按钮）。
  it("disables the address edit entry when capabilities forbid editing (FR-006)", () => {
    const frozenView = {
      ...checkoutView,
      capabilities: {
        can_edit_address: false,
        can_change_shipping: false,
        can_apply_promotion: false,
        can_pay: true,
      },
    } as unknown as CheckoutView;

    renderOrderPayment(order, frozenView, countries);

    expect(
      (screen.getByTestId("edit-address") as HTMLButtonElement).disabled,
    ).toBe(true);
  });

  // D15 切片3 AC-011/FR-005：认证需求 = 是时服务端只投影可认证入口，前端仅负责解释
  it("shows the authentication notice when the projection flags a capable entry (D15c AC-011)", () => {
    const viewWithAuth = {
      ...checkoutView,
      payment: {
        available_payment_methods: [
          {
            ...stripeMethod,
            kind: "card",
            frontend_kind: "inline",
            option_id: "opt_card",
            method_key: "card",
            display_name: "Card",
            requires_authentication: true,
          },
        ],
        requires_authentication: true,
      },
    } as unknown as CheckoutView;

    renderOrderPayment(order, viewWithAuth, countries);

    expect(screen.getByTestId("authentication-required-notice")).toBeTruthy();
    expect(screen.queryByTestId("no-payment-method")).toBeNull();
  });

  // D15 切片3 AC-011/FR-005：无可用入口时给显式提示（不静默空白，也不降级到弱认证入口）
  it("shows the no-payment-method notice when the projection has no entry (D15c AC-011)", () => {
    const viewWithoutMethods = {
      ...checkoutView,
      payment: { available_payment_methods: [], requires_authentication: true },
    } as unknown as CheckoutView;

    renderOrderPayment(
      { ...order, payment_methods: [] } as unknown as Order,
      viewWithoutMethods,
      countries,
    );

    expect(screen.getByTestId("no-payment-method")).toBeTruthy();
    expect(screen.queryByTestId("authentication-required-notice")).toBeNull();
  });
});
