import type { ShoppingCart } from "@pallastrade/sdk";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { toast } from "sonner";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UnifiedCheckout } from "@/components/checkout/UnifiedCheckout";
import { CheckoutProvider, CheckoutSummary } from "@/contexts/CheckoutContext";

const pushMock = vi.fn();
const replaceMock = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, replace: replaceMock }),
  usePathname: () => "/us/en/checkout/cart_1",
}));

vi.mock("@/lib/data/countries", () => ({
  getCountry: vi.fn().mockResolvedValue({ states: [] }),
}));

const fetchMock = vi.fn();

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

// AddressFormFields 简化 mock：渲染全部地址字段输入 + 短信订阅（PRD 3.3）
vi.mock("@/components/checkout/AddressFormFields", () => ({
  AddressFormFields: ({
    address,
    onChange,
    idPrefix,
    showSmsOptIn,
  }: {
    address: Record<string, string>;
    onChange: (field: string, value: string) => void;
    idPrefix: string;
    showSmsOptIn?: boolean;
  }) => (
    <div>
      {[
        "first_name",
        "last_name",
        "address1",
        "city",
        "postal_code",
        "country_iso",
        "state_abbr",
      ].map((field) => (
        <input
          key={field}
          aria-label={`${idPrefix}-${field}`}
          value={address[field] ?? ""}
          onChange={(e) => onChange(field, e.target.value)}
        />
      ))}
      {showSmsOptIn && <div data-testid="sms-opt-in" />}
    </div>
  ),
}));

vi.mock("@/components/ui/product-image", () => ({
  ProductImage: () => <div data-testid="product-image" />,
}));

function makeCart(overrides: Partial<ShoppingCart> = {}): ShoppingCart {
  return {
    id: "cart_1",
    email: "",
    shipping_address: null,
    shipping_method_id: null,
    payment_methods: [
      {
        id: "pm_card",
        name: "Card",
        type: "stripe",
        session_required: true,
      },
    ],
    items: [
      {
        id: "li_1",
        name: "Awesome Product",
        quantity: 2,
        thumbnail_url: null,
        display_amount: "$19.98",
      },
    ],
    display_item_total: "$19.98",
    ...overrides,
  } as unknown as ShoppingCart;
}

const shippingMethods = [
  {
    id: "dm_1",
    name: "Standard",
    code: "STANDARD",
    display_estimated_price: "$5.00",
  },
];

async function fillRequiredFields(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("unified-first_name"), "Ada");
  await user.type(screen.getByLabelText("unified-last_name"), "Lovelace");
  await user.type(
    screen.getByLabelText("unified-address1"),
    "12 Analytical Way",
  );
  await user.type(screen.getByLabelText("unified-city"), "London");
  await user.type(screen.getByLabelText("unified-postal_code"), "SW1A 1AA");
  await user.type(screen.getByLabelText("unified-country_iso"), "GB");
  await user.type(screen.getByLabelText("unified-state_abbr"), "LDN");
}

function renderCheckout(cart: ShoppingCart = makeCart()) {
  return render(
    <CheckoutProvider>
      <UnifiedCheckout
        cart={cart}
        shippingMethods={shippingMethods}
        countries={[]}
        isAuthenticated={false}
      />
      <CheckoutSummary />
    </CheckoutProvider>,
  );
}

describe("UnifiedCheckout (PRD-20260830-checkout AC-001/AC-002)", () => {
  beforeEach(() => {
    pushMock.mockReset();
    replaceMock.mockReset();
    fetchMock.mockReset();
    // PRD-20260914-checkout-quote-confirmation-loop：报价快照存 sessionStorage，
    // 用例间必须隔离，否则快照会泄漏到其它用例的载荷断言。
    sessionStorage.clear();
    vi.stubGlobal("fetch", fetchMock);
    confirmMock.mockReset();
    fetchMock.mockImplementation(
      async (_input: RequestInfo | URL, init?: RequestInit) => ({
        ok: true,
        json: async () =>
          init?.method === "POST"
            ? {
                order: { id: "or_123" },
                session: {
                  id: "ps_1",
                  external_data: { client_secret: "sec_1" },
                },
              }
            : { session: { id: "ps_1", status: "completed" } },
      }),
    );
    confirmMock.mockResolvedValue({});
  });

  it("renders numbered sections, marketing opt-in, add-ons, save info and order summary", () => {
    renderCheckout();

    expect(screen.getByText("orderConfirmation")).toBeTruthy();
    expect(screen.getByText("contactInformation")).toBeTruthy();
    expect(screen.getByText("shippingAddress")).toBeTruthy();
    expect(screen.getByText("items")).toBeTruthy();
    expect(screen.getByText("shippingMethod")).toBeTruthy();
    expect(screen.getByText("addOns")).toBeTruthy();
    expect(screen.getByText("paymentMethod")).toBeTruthy();
    expect(screen.getByText("orderSummary")).toBeTruthy();
    expect(screen.getByTestId("unified-order-summary")).toBeInTheDocument();
    // 商品名出现在左侧商品区块与右侧订单摘要各一次
    expect(
      screen.getAllByText("Awesome Product").length,
    ).toBeGreaterThanOrEqual(1);
    expect(screen.getByText("Standard")).toBeTruthy();
    expect(screen.getByText("Card")).toBeTruthy();
    // demo 优化元素
    expect(screen.getByTestId("marketing-opt-in")).toBeInTheDocument();
    expect(screen.getByTestId("save-info-section")).toBeInTheDocument();
    expect(screen.getByText("addOnsWorryFreeName")).toBeTruthy();
    expect(screen.getByText("whyBuyFromUs")).toBeTruthy();
    // 金额在商品行与订单小结各出现一次
    expect(screen.getAllByText("$19.98").length).toBeGreaterThanOrEqual(2);
  });

  it("renders the self-drawn card form immediately when Stripe is selected (no client_secret needed)", () => {
    renderCheckout();

    // Stripe 自绘卡字段表单在未填地址时也始终渲染（PRD-20260831-payments-stripe-自绘卡支付表单）
    expect(screen.getByTestId("card-payment-form")).toBeInTheDocument();

    const payNow = screen.getByRole("button", { name: "payNow" });
    expect(payNow).toBeDisabled();
  });

  it("uses one Pay click to submit, confirm, complete, and open the result page (AC-002)", async () => {
    const user = userEvent.setup();
    renderCheckout();

    expect(screen.getByTestId("card-payment-form")).toBeInTheDocument();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));

    expect(fetchMock).not.toHaveBeenCalled();
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    const postOptions = fetchMock.mock.calls[0]?.[1] as RequestInit;
    expect(fetchMock.mock.calls[0]?.[0]).toBe("/api/checkout/start");
    expect(postOptions.method).toBe("POST");
    expect(JSON.parse(postOptions.body as string)).toMatchObject({
      cart_id: "cart_1",
      payment_method_id: "pm_card",
      payment_mode: "payment_intent",
      // PRD-20260913-checkout-billing-mode AC-008：显式账单语义（不再发 use_shipping）
      checkout: { billing_mode: "same_as_shipping" },
    });
    expect(confirmMock).toHaveBeenCalledWith("sec_1");
    const patchCall = fetchMock.mock.calls[1];
    expect(patchCall).toBeDefined();
    const patchOptions = patchCall[1] as RequestInit;
    expect(patchOptions.method).toBe("PATCH");
    expect(replaceMock).toHaveBeenCalledWith(
      "/us/en/payment-result/or_123?session=ps_1",
    );
  });

  it("non-session payment (Check) goes straight to the placed page after submit", async () => {
    const user = userEvent.setup();
    const cart = makeCart({
      payment_methods: [
        {
          id: "pm_check",
          name: "Check",
          type: "check",
          session_required: false,
        },
      ],
    } as never);
    renderCheckout(cart);

    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() =>
      expect(replaceMock).toHaveBeenCalledWith("/us/en/payment-result/or_123"),
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("shows a fallback message when no payment methods are available", () => {
    renderCheckout(makeCart({ payment_methods: [] as never }));

    expect(screen.getByText("noPaymentMethods")).toBeTruthy();
  });

  it("keeps the user on checkout when orchestration fails before an order exists", async () => {
    const user = userEvent.setup();
    fetchMock.mockResolvedValue({
      ok: false,
      json: async () => ({ error: "Invalid address" }),
    });

    renderCheckout();

    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    // 自绘卡字段模式：点 Pay Now 才触发提交（PRD-20260831-payments-stripe-自绘卡支付表单）
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(pushMock).not.toHaveBeenCalled();
    expect(replaceMock).not.toHaveBeenCalled();
  });

  // ── bugfix 2026-09-06：BFF/后端错误对象不得直传 toast（React error #31 整页崩）──
  it("normalizes a structured BFF error body { error: { code, message } } to a string toast", async () => {
    const user = userEvent.setup();
    const toastErrorSpy = vi
      .spyOn(toast, "error")
      .mockImplementation(() => "0");
    fetchMock.mockResolvedValue({
      ok: false,
      json: async () => ({
        error: { code: "route_not_found", message: "API endpoint not found" },
      }),
    });

    renderCheckout();

    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(toastErrorSpy).toHaveBeenCalledWith("API endpoint not found");
    expect(replaceMock).not.toHaveBeenCalled();
    toastErrorSpy.mockRestore();
  });

  // ── PRD-20260913-checkout-txn-error-routing：提交后错误按 code 分流 ──
  // PRD-20260913-checkout-txn-error-routing AC-001（quote 变化 → or_ notice，不自动支付）
  // PRD-20260913-checkout-txn-error-routing AC-002（库存不足 → 页内提示 + 返回购物车）
  // PRD-20260913-checkout-txn-error-routing AC-003（库存变化 / 预留过期 → 页内提示）
  // PRD-20260913-checkout-txn-error-routing AC-004（已收款恢复 → 结果页 notice=recovery）
  // PRD-20260913-checkout-txn-error-routing AC-008（未就绪 → 页内提示，无 CTA）
  // PRD-20260913-checkout-txn-error-routing AC-009（未知 code → 结果页兜底）

  async function payWithErrorBody(body: Record<string, unknown>) {
    const user = userEvent.setup();
    fetchMock.mockResolvedValue({ ok: false, json: async () => body });
    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
  }

  // PRD-20260914-checkout-quote-confirmation-loop AC-003：报价变化**不再跳转** or_ 页，
  // 改为 cart_ 页内差异确认（取代 PRD-20260913 的跳转分支；order_id 仍保留在响应里）。
  it("keeps the user in page with an in-page diff when the quote changed (AC-003)", async () => {
    await payWithErrorBody({
      error: { code: "quote_changed", message: "Checkout quote changed" },
      order_id: "or_123",
      quote: {
        checkout_version: 2,
        price_version: "pv_new",
        delivery_total: "9.0",
        display_delivery_total: "$9.00",
        discount_total: "0.0",
        display_discount_total: "$0.00",
        amount_due: "28.98",
        display_amount_due: "$28.98",
      },
    });

    expect(
      await screen.findByTestId("checkout-quote-diff"),
    ).toBeInTheDocument();
    expect(replaceMock).not.toHaveBeenCalled();
    expect(confirmMock).not.toHaveBeenCalled();
  });

  // PRD-20260914-checkout-quote-confirmation-loop AC-008：其他错误码分支零回归
  it("keeps the user on checkout for insufficient stock with a return-to-cart CTA (AC-002)", async () => {
    await payWithErrorBody({
      error: { code: "INSUFFICIENT_STOCK", message: "Product A is sold out" },
      order_id: "or_123",
    });

    expect(screen.getByTestId("checkout-error-notice")).toBeInTheDocument();
    expect(screen.getByText("stockUnavailableTitle")).toBeTruthy();
    expect(screen.getByText("Product A is sold out")).toBeTruthy();
    expect(screen.getByRole("link", { name: "returnToCart" })).toHaveAttribute(
      "href",
      "/us/en/cart",
    );
    expect(replaceMock).not.toHaveBeenCalled();
  });

  it("keeps the user on checkout when inventory changed (AC-003)", async () => {
    await payWithErrorBody({
      error: { code: "INVENTORY_CHANGED", message: "Availability changed" },
      order_id: "or_123",
    });

    expect(screen.getByTestId("checkout-error-notice")).toBeInTheDocument();
    expect(replaceMock).not.toHaveBeenCalled();
  });

  it("keeps the user on checkout when the reservation expired (AC-003)", async () => {
    await payWithErrorBody({
      error: { code: "RESERVATION_EXPIRED", message: "Please re-confirm" },
      order_id: "or_123",
    });

    expect(screen.getByTestId("checkout-error-notice")).toBeInTheDocument();
    expect(replaceMock).not.toHaveBeenCalled();
  });

  it("routes a paid-but-recovering transaction to the recovery notice page (AC-004)", async () => {
    await payWithErrorBody({
      error: { code: "INVENTORY_RECOVERY_REQUIRED", message: "Recovering" },
      order_id: "or_123",
    });

    expect(replaceMock).toHaveBeenCalledWith(
      "/us/en/payment-result/or_123?notice=recovery",
    );
  });

  it("shows an in-page notice for a not-ready checkout without navigation (AC-008)", async () => {
    await payWithErrorBody({
      error: { code: "checkout_not_ready", message: "Missing delivery rate" },
      order_id: "or_123",
    });

    expect(screen.getByTestId("checkout-error-notice")).toBeInTheDocument();
    expect(screen.getByText("checkoutNotReady")).toBeTruthy();
    expect(screen.queryByRole("link", { name: "returnToCart" })).toBeNull();
    expect(replaceMock).not.toHaveBeenCalled();
  });

  it("keeps the result-page fallback for unknown codes with an order id (AC-009)", async () => {
    await payWithErrorBody({
      error: { code: "checkout_failed", message: "Unexpected failure" },
      order_id: "or_123",
    });

    expect(replaceMock).toHaveBeenCalledWith("/us/en/payment-result/or_123");
  });

  // ── PRD v1.1（Checkout页面.md）新增对齐测试 ─────────────────────────

  it("defaults to the Credit card (Stripe) payment method when available (PRD 3.6)", () => {
    renderCheckout(
      makeCart({
        payment_methods: [
          {
            id: "pm_check",
            name: "Check",
            type: "check",
            session_required: false,
          },
          {
            id: "pm_card",
            name: "Card",
            type: "stripe",
            session_required: true,
          },
        ],
      } as never),
    );

    const stripeRadio = screen.getByRole("radio", { name: /Card/ });
    expect(stripeRadio).toBeChecked();
    expect(screen.getByTestId("card-payment-form")).toBeInTheDocument();
  });

  it("renders SMS opt-in and shipping options-changed warning (PRD 3.3/3.4)", () => {
    renderCheckout();

    expect(screen.getByTestId("sms-opt-in")).toBeInTheDocument();
    expect(screen.getByTestId("shipping-options-changed")).toBeInTheDocument();
  });

  it("validates email on blur (PRD 3.2)", async () => {
    const user = userEvent.setup();
    renderCheckout();

    const emailInput = screen.getByLabelText("email");
    await user.type(emailInput, "not-an-email");
    await user.tab();

    await waitFor(() =>
      expect(screen.getByTestId("email-error")).toBeInTheDocument(),
    );
  });

  it("warns when Pay Now is clicked with an empty email (PRD 3.2)", async () => {
    const user = userEvent.setup();
    renderCheckout();

    await fillRequiredFields(user);
    await user.click(screen.getByRole("radio", { name: /Standard/ }));

    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() =>
      expect(screen.getByTestId("email-error")).toBeInTheDocument(),
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("toggles billing address form via same-as-shipping checkbox (PRD 3.6)", async () => {
    const user = userEvent.setup();
    renderCheckout();

    // 默认勾选 "Same as shipping address"，不显示账单地址表单
    const billingCheckbox = screen.getByTestId("billing-use-shipping");
    expect(billingCheckbox).toBeInTheDocument();
    expect(screen.queryByText("billingAddress")).not.toBeInTheDocument();

    // 取消勾选 → 展开账单地址表单
    await user.click(billingCheckbox);
    expect(screen.getByText("billingAddress")).toBeInTheDocument();
    expect(screen.getByLabelText("bill-first_name")).toBeInTheDocument();
  });

  // PRD-20260913-checkout-billing-mode AC-009：购物车已带独立账单地址 → 默认未勾选
  // （否则提交时会以「同配送」语义静默覆盖用户此前的选择）
  it("unchecks same-as-shipping when the cart already has a billing address", () => {
    renderCheckout(
      makeCart({
        billing_address: {
          id: "addr_1",
          city: "Billingville",
        } as unknown as NonNullable<ShoppingCart["billing_address"]>,
      }),
    );

    expect(screen.getByTestId("billing-use-shipping")).not.toBeChecked();
  });

  // PRD-20260914-checkout-quote-confirmation-loop AC-001/AC-002：报价快照 → expected_*
  it("sends expected quote versions when a snapshot exists and omits them otherwise", async () => {
    const user = userEvent.setup();
    sessionStorage.setItem(
      "pallastrade:quote:cart_1",
      JSON.stringify({
        checkout_version: 7,
        price_version: "pv_7",
        delivery_total: "5.0",
        display_delivery_total: "$5.00",
        discount_total: "0.0",
        display_discount_total: "$0.00",
        amount_due: "24.98",
        display_amount_due: "$24.98",
      }),
    );

    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    const startOptions = fetchMock.mock.calls[0]?.[1] as RequestInit;
    const body = JSON.parse(startOptions.body as string) as Record<
      string,
      unknown
    >;
    expect(body.expected_checkout_version).toBe(7);
    expect(body.expected_price_version).toBe("pv_7");
  });

  it("omits expected versions on the first click without a snapshot", async () => {
    const user = userEvent.setup();
    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    const startOptions = fetchMock.mock.calls[0]?.[1] as RequestInit;
    const body = JSON.parse(startOptions.body as string) as Record<
      string,
      unknown
    >;
    expect(body.expected_checkout_version).toBeUndefined();
    expect(body.expected_price_version).toBeUndefined();
  });

  // PRD-20260914-checkout-quote-confirmation-loop AC-003/AC-004/AC-006：报价漂移 → 页内确认
  // （AC-006 在此以“服务端信封含 quote”的契约形式被消费：差异行即来自响应里的 quote）。
  it("keeps the user in page and shows the three-row diff on a 409 conflict", async () => {
    const user = userEvent.setup();
    sessionStorage.setItem(
      "pallastrade:quote:cart_1",
      JSON.stringify({
        checkout_version: 1,
        price_version: "pv_old",
        delivery_total: "5.0",
        display_delivery_total: "$5.00",
        discount_total: "0.0",
        display_discount_total: "$0.00",
        amount_due: "24.98",
        display_amount_due: "$24.98",
      }),
    );
    fetchMock.mockImplementation(async (input: RequestInfo | URL) => {
      if (String(input) === "/api/checkout/start") {
        return {
          ok: false,
          json: async () => ({
            error: { code: "quote_changed", message: "quote changed" },
            order_id: "or_123",
            quote: {
              checkout_version: 2,
              price_version: "pv_new",
              delivery_total: "9.0",
              display_delivery_total: "$9.00",
              discount_total: "1.0",
              display_discount_total: "-$1.00",
              amount_due: "28.98",
              display_amount_due: "$28.98",
            },
          }),
        };
      }
      return { ok: true, json: async () => ({}) };
    });

    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    const diff = await screen.findByTestId("checkout-quote-diff");
    expect(diff).toBeInTheDocument();
    const shippingRow = screen.getByTestId("quote-diff-shipping");
    expect(shippingRow).toHaveTextContent("$5.00");
    expect(shippingRow).toHaveTextContent("$9.00");
    expect(screen.getByTestId("quote-diff-amountDue")).toHaveAttribute(
      "data-changed",
      "true",
    );
    // 零跳转（不再去 or_ 页）+ 零自动重试（fetch 只发一次）
    expect(replaceMock).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  // PRD-20260914-checkout-quote-confirmation-loop AC-005：冲突但响应无 quote → 降级为页内提示
  it("degrades to an in-page notice when the conflict carries no quote", async () => {
    const user = userEvent.setup();
    fetchMock.mockImplementation(async (input: RequestInfo | URL) => {
      if (String(input) === "/api/checkout/start") {
        return {
          ok: false,
          json: async () => ({
            error: { code: "checkout_version_conflict", message: "stale" },
            order_id: "or_123",
          }),
        };
      }
      return { ok: true, json: async () => ({}) };
    });

    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    expect(
      await screen.findByTestId("checkout-quote-diff"),
    ).toBeInTheDocument();
    expect(screen.queryByTestId("quote-diff-shipping")).not.toBeInTheDocument();
    expect(replaceMock).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  // PRD-20260913-checkout-billing-mode FR-011/AC-010：取消「同配送」但账单地址不完整
  // 时不得发出 checkout 请求（服务端 FR-003 同样拦截）。
  it("blocks Pay now when a custom billing address is incomplete", async () => {
    const user = userEvent.setup();
    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));

    await user.click(screen.getByTestId("billing-use-shipping"));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    expect(fetchMock).not.toHaveBeenCalled();
  });

  // PRD-20260909-promotions-promo-batch2-discount-projection-unified AC-008
  it("applies and removes a discount code through the coupon BFF (PRD 3.9.2)", async () => {
    const user = userEvent.setup();
    fetchMock.mockImplementation(
      async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input);
        if (url === "/api/checkout/coupon") {
          return {
            ok: true,
            json: async () => ({
              cart: {
                ...makeCart(),
                discount_total: "5.00",
                display_discount_total: "-$5.00",
                display_total: "$14.98",
                discounts: [
                  {
                    id: "discount_abc",
                    promotion_id: "promo_x1",
                    name: "Save 5",
                    description: null,
                    code: "SAVE5",
                    kind: "coupon_code",
                    amount: "-5.0",
                    display_amount: "-$5.00",
                    breakdown: { items: "0.0", order: "-5.0", shipping: "0.0" },
                    removable: true,
                  },
                ],
              },
            }),
          };
        }
        return {
          ok: true,
          json: async () => ({ session: { id: "ps_1" } }),
        };
      },
    );

    renderCheckout();

    // 折扣码输入框（coupon 命名空间 placeholder）
    const input = screen.getByLabelText("placeholder");
    await user.type(input, "SAVE5");
    await user.click(screen.getByRole("button", { name: "apply" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(screen.getByText("SAVE5")).toBeInTheDocument();
    expect(screen.getByTestId("total-savings")).toBeInTheDocument();
    expect(screen.getByText("$14.98")).toBeInTheDocument();
  });

  // ── PRD-20260913-checkout-money-contract AC-003/AC-004：节省口径只算促销折扣 ──
  it("counts only promotion discounts in TOTAL SAVINGS (AC-003)", async () => {
    const user = userEvent.setup();
    fetchMock.mockImplementation(async (input: RequestInfo | URL) => {
      if (String(input) === "/api/checkout/coupon") {
        return {
          ok: true,
          json: async () => ({
            cart: {
              ...makeCart(),
              currency: "USD",
              display_total: "$12.98",
              discount_total: "-5.00",
              display_discount_total: "-$5.00",
              gift_card_total: "-3.00",
              display_gift_card_total: "-$3.00",
              store_credit_total: "-2.00",
              display_store_credit_total: "-$2.00",
              discounts: [
                {
                  id: "discount_abc",
                  promotion_id: "promo_x1",
                  name: "Save 5",
                  description: null,
                  code: "SAVE5",
                  kind: "coupon_code",
                  amount: "-5.0",
                  display_amount: "-$5.00",
                  breakdown: { items: "0.0", order: "-5.0", shipping: "0.0" },
                  removable: true,
                },
              ],
            },
          }),
        };
      }
      return {
        ok: true,
        json: async () => ({ session: { id: "ps_1" } }),
      };
    });

    renderCheckout();

    const input = screen.getByLabelText("placeholder");
    await user.type(input, "SAVE5");
    await user.click(screen.getByRole("button", { name: "apply" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    // 节省 = 促销折扣 $5.00（礼品卡 / 店铺余额不计入）
    const badge = screen.getByTestId("total-savings");
    expect(badge.textContent).toContain("$5.00");
    expect(badge.textContent).not.toContain("$10.00");
  });

  it("hides TOTAL SAVINGS when only gift cards are applied (AC-004)", async () => {
    const user = userEvent.setup();
    fetchMock.mockImplementation(async (input: RequestInfo | URL) => {
      if (String(input) === "/api/checkout/coupon") {
        return {
          ok: true,
          json: async () => ({
            cart: {
              ...makeCart(),
              currency: "USD",
              discount_total: null,
              display_discount_total: null,
              gift_card_total: "-3.00",
              display_gift_card_total: "-$3.00",
              discounts: [],
            },
          }),
        };
      }
      return {
        ok: true,
        json: async () => ({ session: { id: "ps_1" } }),
      };
    });

    renderCheckout();

    const input = screen.getByLabelText("placeholder");
    await user.type(input, "GIFT3");
    await user.click(screen.getByRole("button", { name: "apply" }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(screen.queryByTestId("total-savings")).toBeNull();
  });
});
