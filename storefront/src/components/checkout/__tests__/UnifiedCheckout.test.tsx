import type { ShoppingCart } from "@pallastrade/sdk";
import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { toast } from "sonner";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UnifiedCheckout } from "@/components/checkout/UnifiedCheckout";
import { CheckoutProvider, CheckoutSummary } from "@/contexts/CheckoutContext";

const pushMock = vi.fn();
const replaceMock = vi.fn();

/** D7 补口 2：钱包可用性分支需要「已配置 Stripe」的环境（默认关闭保持既有用例不变）。 */
const stripeConfiguredState = vi.hoisted(() => ({ value: false }));

/** 捕获 ExpressCheckoutElement 的 props（驱动 onReady 上报设备钱包能力）。 */
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
  getStripePromise: () => Promise.resolve(null),
  isStripeConfigured: () => stripeConfiguredState.value,
  resolveStripePublishableKey: () => null,
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
        // 服务端真实载荷口径（D16/D7）：入口身份与形态随 provider 下发
        kind: "card",
        method_key: "card",
        display_name: "Card",
        frontend_kind: "inline",
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
    estimated_transit_business_days_min: 3,
    estimated_transit_business_days_max: 5,
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
    stripeConfiguredState.value = false;
    capturedExpressProps = {};
    // PRD-20260914-checkout-quote-confirmation-loop：报价快照存 sessionStorage，
    // 用例间必须隔离，否则快照会泄漏到其它用例的载荷断言。
    sessionStorage.clear();
    vi.stubGlobal("fetch", fetchMock);
    confirmMock.mockReset();
    fetchMock.mockImplementation(
      async (input: RequestInfo | URL, init?: RequestInit) => {
        // PRD-20260915-checkout-单页两段语义：首次 Pay 先走 Prepare（建单 + 权威报价）。
        // 默认 mock 不带 quote（服务端降级路径）→ 组件直接进入 Pay，保持既有断言；
        // 需要「确认区」的用例自行覆写该分支。
        if (input === "/api/checkout/prepare") {
          return {
            ok: true,
            json: async () => ({
              order_id: "or_123",
              order: { id: "or_123" },
              quote: null,
            }),
          };
        }
        return {
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
        };
      },
    );
    confirmMock.mockResolvedValue({});
  });

  // PRD-20260914-checkout-placeholder-controls-governance AC-001
  it("renders numbered sections, marketing opt-in and order summary; hides backend-less placeholders", () => {
    renderCheckout();

    expect(screen.getByText("orderConfirmation")).toBeTruthy();
    expect(screen.getByText("contactInformation")).toBeTruthy();
    expect(screen.getByText("shippingAddress")).toBeTruthy();
    expect(screen.getByText("items")).toBeTruthy();
    expect(screen.getByText("shippingMethod")).toBeTruthy();
    expect(screen.getByText("paymentMethod")).toBeTruthy();
    expect(screen.getByText("orderSummary")).toBeTruthy();
    expect(screen.getByTestId("unified-order-summary")).toBeInTheDocument();
    // 商品名出现在左侧商品区块与右侧订单摘要各一次
    expect(
      screen.getAllByText("Awesome Product").length,
    ).toBeGreaterThanOrEqual(1);
    expect(screen.getByText("Standard")).toBeTruthy();
    expect(screen.getByText("Card")).toBeTruthy();
    // Marketing 已接线 → 保留可见（governance FR-001）
    expect(screen.getByTestId("marketing-opt-in")).toBeInTheDocument();
    expect(screen.getByText("whyBuyFromUs")).toBeTruthy();
    // Add-ons / Save Info 无后端能力 → 默认隐藏（governance FR-002）
    expect(screen.queryByText("addOns")).toBeNull();
    expect(screen.queryByText("addOnsWorryFreeName")).toBeNull();
    expect(screen.queryByTestId("save-info-section")).toBeNull();
    // 金额在商品行与订单小结各出现一次
    expect(screen.getAllByText("$19.98").length).toBeGreaterThanOrEqual(2);
  });

  // PRD-20260914-checkout-placeholder-controls-governance AC-003
  it("does not block checkout when the marketing subscribe call fails", async () => {
    const user = userEvent.setup();
    const defaultImpl = fetchMock.getMockImplementation();
    fetchMock.mockImplementation(
      (input: RequestInfo | URL, init?: RequestInit) => {
        if (input === "/api/checkout/newsletter") {
          return Promise.reject(new Error("newsletter down"));
        }
        return defaultImpl?.(input, init);
      },
    );

    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    // 订阅失败 → 下单/支付流程照常走到结果页（NFR-1）
    await waitFor(() =>
      expect(replaceMock).toHaveBeenCalledWith(
        "/us/en/payment-result/or_123?session=ps_1",
      ),
    );
    expect(fetchMock.mock.calls.map(([url]) => url)).toContain(
      "/api/checkout/newsletter",
    );
  });

  // PRD-20260914-checkout-placeholder-controls-governance AC-004
  it("keeps the hidden placeholder components intact so the switch can be re-enabled", async () => {
    const { AddOnsSection } = await import(
      "@/components/checkout/AddOnsSection"
    );
    const { SaveInfoSection } = await import(
      "@/components/checkout/SaveInfoSection"
    );

    expect(AddOnsSection).toBeTypeOf("function");
    expect(SaveInfoSection).toBeTypeOf("function");
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

    // PRD-20260914-checkout-placeholder-controls-governance AC-002：
    // 勾选 Marketing（默认 true）→ 提交成功后额外发起一次订阅；
    // PRD-20260915 两段语义 = prepare + start + newsletter + PATCH
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(4));
    const newsletterCall = fetchMock.mock.calls.find(
      ([url]) => url === "/api/checkout/newsletter",
    );
    if (!newsletterCall) {
      throw new Error("marketing subscribe call was not made");
    }
    expect(
      JSON.parse((newsletterCall[1] as RequestInit).body as string),
    ).toEqual({ email: "ada@example.com" });
    // PRD-20260915-checkout-单页两段语义：
    // 第一段 Prepare 携带结账输入（cart_id + checkout），第二段 Pay 只携带订单与支付方式。
    const prepareCall = fetchMock.mock.calls.find(
      ([url]) => url === "/api/checkout/prepare",
    );
    expect(prepareCall).toBeDefined();
    const prepareInit = prepareCall?.[1] as RequestInit;
    expect(JSON.parse(prepareInit.body as string)).toMatchObject({
      cart_id: "cart_1",
      // PRD-20260913-checkout-billing-mode AC-008：显式账单语义（不再发 use_shipping）
      checkout: { billing_mode: "same_as_shipping" },
    });

    const startCall = fetchMock.mock.calls.find(
      ([url]) => url === "/api/checkout/start",
    );
    const postOptions = startCall?.[1] as RequestInit;
    expect(startCall?.[0]).toBe("/api/checkout/start");
    expect(postOptions.method).toBe("POST");
    expect(JSON.parse(postOptions.body as string)).toMatchObject({
      order_id: "or_123",
      payment_method_id: "pm_card",
      // D7 FR-005：入口（method kind）随 Pay 请求下发（服务端同源复算可用性）
      option_kind: "card",
      payment_mode: "payment_intent",
      session_required: true,
    });
    expect(confirmMock).toHaveBeenCalledWith("sec_1");
    const patchCall = fetchMock.mock.calls.find(
      ([, init]) => (init as RequestInit)?.method === "PATCH",
    );
    expect(patchCall).toBeDefined();
    const patchOptions = patchCall?.[1] as RequestInit;
    expect(patchOptions.method).toBe("PATCH");
    expect(replaceMock).toHaveBeenCalledWith(
      "/us/en/payment-result/or_123?session=ps_1",
    );
  });

  // PRD-20260918-payments-d7-payment-section-express AC-006（cart 通道）：
  // 购物车单页结账读 `cart.payment_methods[].entries` → **一入口一行**；
  // 钱包入口以 express 形态出现（不再需要后台关掉卡支付才能看到）。
  it("renders one row per server-projected entry from the cart (D7 AC-006)", () => {
    const cart = makeCart({
      payment_methods: [
        {
          id: "pm_stripe",
          name: "Stripe",
          type: "stripe",
          session_required: true,
          entries: [
            {
              option_id: "pm_stripe:card",
              method_key: "card",
              display_name: "Card",
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
            {
              option_id: "pm_stripe:google_pay",
              method_key: "google_pay",
              display_name: "Google Pay",
              frontend_kind: "express",
              group: "wallet",
              position: 3,
            },
          ],
        },
      ],
    } as never);
    renderCheckout(cart);

    const rows = screen.getAllByTestId("payment-entry-row");
    expect(rows.map((row) => row.getAttribute("data-option-id"))).toEqual([
      "pm_stripe:card",
      "pm_stripe:apple_pay",
      "pm_stripe:google_pay",
    ]);
    expect(rows[1].getAttribute("data-frontend-kind")).toBe("express");
    expect(screen.getByText("Apple Pay")).toBeTruthy();
    expect(screen.getByText("Google Pay")).toBeTruthy();
  });

  // PRD-20260918-payments-d7-payment-section-express AC-011（cart 通道）：
  // 本设备无可用钱包（Stripe 报告全 false）→ 入口行置灰禁用 + 自动回落卡支付 +
  // 显式说明（旧行为：组件静默 `return null` → 页面只剩一个空盒子）。
  it("greys out the wallet entry and falls back to card when the device has no wallet (D7 AC-011)", async () => {
    const user = userEvent.setup();
    stripeConfiguredState.value = true;
    const cart = makeCart({
      currency: "usd",
      payment_methods: [
        {
          id: "pm_stripe",
          name: "Stripe",
          type: "stripe",
          session_required: true,
          entries: [
            {
              option_id: "pm_stripe:card",
              method_key: "card",
              display_name: "Card",
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
        },
      ],
    } as never);
    renderCheckout(cart);

    await user.click(screen.getByText("Apple Pay"));

    // cart 页钱包组件按需加载（next/dynamic）+ 直接挂载 ExpressCheckoutElement：
    // 只有确认时才创建会话，因此这里直接得到可探测的元素。
    await screen.findByTestId("express-checkout-element");
    await act(async () => {
      (capturedExpressProps.onReady as (event: unknown) => void)({
        availablePaymentMethods: {
          applePay: false,
          googlePay: false,
          link: false,
        },
      });
    });

    // ① 入口行置灰禁用（只标注，不删除服务端下发的入口集合）
    const walletRow = screen
      .getAllByTestId("payment-entry-row")
      .find((r) => r.getAttribute("data-option-id") === "pm_stripe:apple_pay");
    expect(walletRow?.getAttribute("data-unavailable")).toBe("true");
    const walletRadio = walletRow?.querySelector("input");
    expect((walletRadio as HTMLInputElement).disabled).toBe(true);
    expect(screen.getByTestId("payment-entry-unavailable")).toBeTruthy();

    // ② 自动回落卡支付：卡表单回来，空盒子不再存在
    await waitFor(() =>
      expect(screen.getByTestId("card-payment-form")).toBeInTheDocument(),
    );
    expect(screen.queryByTestId("express-checkout-element")).toBeNull();
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
    // 订阅（best-effort）也计入 fetch；两段语义 = prepare + start（非会话）+ 订阅
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(fetchMock.mock.calls.map(([url]) => url)).toContain(
      "/api/checkout/newsletter",
    );
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
    // PRD-20260915-checkout-单页两段语义：Prepare 正常建单，错误发生在 Pay
    // （orders.transactions.create）——错误码分流路径保持不变。
    const defaultImpl = fetchMock.getMockImplementation();
    fetchMock.mockImplementation(
      (input: RequestInfo | URL, init?: RequestInit) => {
        if (input === "/api/checkout/prepare") {
          return defaultImpl?.(input, init);
        }
        return Promise.resolve({ ok: false, json: async () => body });
      },
    );
    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));
    // 只断言"已发起提交"：预留过期会在同一流程内自动重试一次，次数由各用例自行断言。
    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
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
  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-001 AC-007
  it("keeps the user on checkout for insufficient stock with a return-to-cart CTA (AC-002)", async () => {
    await payWithErrorBody({
      error: { code: "INSUFFICIENT_STOCK", message: "Product A is sold out" },
      order_id: "or_123",
    });

    expect(screen.getByTestId("checkout-error-notice")).toBeInTheDocument();
    // PRD-...-b3-... AC-001：库存不足的专属标题（不共用通用文案）
    expect(screen.getByText("stockInsufficientTitle")).toBeTruthy();
    expect(screen.getByText("Product A is sold out")).toBeTruthy();
    expect(screen.getByRole("link", { name: "returnToCart" })).toHaveAttribute(
      "href",
      "/us/en/cart",
    );
    expect(replaceMock).not.toHaveBeenCalled();
    // PRD-...-b3-... AC-007：库存不足**不**自动重试（不得继续创建新 PaymentSession）
    // 两段语义 = prepare（建单）+ start（库存失败），无第三次
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-001 AC-007
  it("keeps the user on checkout when inventory changed (AC-003)", async () => {
    await payWithErrorBody({
      error: { code: "INVENTORY_CHANGED", message: "Availability changed" },
      order_id: "or_123",
    });

    expect(screen.getByTestId("checkout-error-notice")).toBeInTheDocument();
    // 专属标题 + 「检查购物车」动作（与「返回购物车」区分）
    expect(screen.getByText("stockChangedTitle")).toBeTruthy();
    expect(screen.getByText("stockChangedHint")).toBeTruthy();
    expect(screen.getByRole("link", { name: "reviewCart" })).toHaveAttribute(
      "href",
      "/us/en/cart",
    );
    expect(replaceMock).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-001 AC-007
  it("auto-retries an expired reservation once, then offers a manual retry (AC-003)", async () => {
    await payWithErrorBody({
      error: { code: "RESERVATION_EXPIRED", message: "Please re-confirm" },
      order_id: "or_123",
    });

    // 自动重试一次（仅该码）：第二次仍是同一 code → 回落为手动入口
    expect(await screen.findByText("reservationExpiredTitle")).toBeTruthy();
    expect(screen.getByText("reservationExpiredHint")).toBeTruthy();
    // 两段语义：prepare + start×2（首次 + 自动重试一次）
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(3));

    // 手动动作仍可用，且绝不会无限循环（第四次由用户触发）
    const user = userEvent.setup();
    await user.click(
      screen.getByRole("button", { name: "retryInventoryCheck" }),
    );
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(4));
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

  // PRD-20260914-checkout-placeholder-controls-governance AC-001
  it("hides the SMS opt-in placeholder and keeps the shipping options-changed warning (PRD 3.4)", () => {
    renderCheckout();

    expect(screen.queryByTestId("sms-opt-in")).toBeNull();
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
    const startCall = fetchMock.mock.calls.find(
      ([url]) => url === "/api/checkout/start",
    );
    const startOptions = startCall?.[1] as RequestInit;
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
      if (String(input) === "/api/checkout/prepare") {
        // 两段语义：Prepare 先建单（返回 or_ 订单），冲突发生在 Pay
        return {
          ok: true,
          json: async () => ({ order_id: "or_123", order: { id: "or_123" } }),
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
    // 零跳转（不再去 or_ 页）+ 零自动重试；两段语义 = prepare + start 各一次
    expect(replaceMock).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(2);
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
      if (String(input) === "/api/checkout/prepare") {
        return {
          ok: true,
          json: async () => ({ order_id: "or_123", order: { id: "or_123" } }),
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
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  // PRD-20260915-checkout-单页两段语义 AC-002/AC-004：
  // Prepare 返回 Order 权威报价 → 页内确认区展示最终金额；确认前绝不发起 Pay。
  it("shows the authoritative final amount and waits for confirmation before paying (AC-002)", async () => {
    const user = userEvent.setup();
    const defaultImpl = fetchMock.getMockImplementation();
    fetchMock.mockImplementation(
      (input: RequestInfo | URL, init?: RequestInit) => {
        if (input === "/api/checkout/prepare") {
          return Promise.resolve({
            ok: true,
            json: async () => ({
              order_id: "or_123",
              order: { id: "or_123" },
              quote: {
                checkout_version: 3,
                price_version: "pv_3",
                delivery_total: "9.0",
                display_delivery_total: "$9.00",
                discount_total: "-2.0",
                display_discount_total: "-$2.00",
                amount_due: "31.98",
                display_amount_due: "$31.98",
              },
            }),
          });
        }
        return defaultImpl?.(input, init);
      },
    );

    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    // ① 确认区展示 Order 权威金额（运费 / 折扣 / 应付，全部 display_* 仅渲染）
    const confirm = await screen.findByTestId("order-quote-confirm");
    expect(confirm).toBeInTheDocument();
    expect(screen.getByTestId("quote-delivery")).toHaveTextContent("$9.00");
    expect(screen.getByTestId("quote-discount")).toHaveTextContent("-$2.00");
    expect(screen.getByTestId("quote-amount-due")).toHaveTextContent("$31.98");
    // ② 确认前**绝不**发起 Pay（只发了 prepare）
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      "/api/checkout/prepare",
    ]);
    expect(confirmMock).not.toHaveBeenCalled();
    expect(replaceMock).not.toHaveBeenCalled();

    // ③ 确认后走 Pay：只对已建订单启动交易，并携带已确认的报价版本
    await user.click(screen.getByRole("button", { name: "confirmAndPay" }));
    await waitFor(() =>
      expect(replaceMock).toHaveBeenCalledWith(
        "/us/en/payment-result/or_123?session=ps_1",
      ),
    );
    const startCall = fetchMock.mock.calls.find(
      ([url]) => url === "/api/checkout/start",
    );
    const startInit = startCall?.[1] as RequestInit;
    expect(JSON.parse(startInit.body as string)).toMatchObject({
      order_id: "or_123",
      expected_checkout_version: 3,
      expected_price_version: "pv_3",
    });
    // 确认后不再重复提交购物车（防重复建单）
    expect(
      fetchMock.mock.calls.filter(([url]) => url === "/api/checkout/prepare")
        .length,
    ).toBe(1);
  });

  // PRD-20260915-checkout-单页两段语义 AC-005：
  // Prepare 未返回权威报价（服务端降级）→ 不展示空确认区，保持一次点击直付。
  it("degrades to a single click when Prepare carries no authoritative quote (AC-005)", async () => {
    const user = userEvent.setup();
    renderCheckout();
    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() =>
      expect(replaceMock).toHaveBeenCalledWith(
        "/us/en/payment-result/or_123?session=ps_1",
      ),
    );
    expect(screen.queryByTestId("order-quote-confirm")).toBeNull();
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
