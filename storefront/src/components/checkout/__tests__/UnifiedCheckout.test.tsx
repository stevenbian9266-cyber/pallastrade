import type { ShoppingCart } from "@pallastrade/sdk";
import { act, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { toast } from "sonner";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UnifiedCheckout } from "@/components/checkout/UnifiedCheckout";
import {
  CheckoutProvider,
  CheckoutSummary,
  useCheckout,
} from "@/contexts/CheckoutContext";

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
  useLocale: () => "en",
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, replace: replaceMock }),
  usePathname: () => "/us/en/checkout/cart_1",
}));

vi.mock("@/lib/data/countries", () => ({
  getCountry: vi.fn().mockResolvedValue({ states: [] }),
}));

const fetchMock = vi.fn();
/**
 * PRD-20260919-shipping-checkout-quote-preview AC-006：预览走**独立** mock。
 * 既让既有「结账链路调用次数」断言不受新增只读请求影响，
 * 也让预览的防抖/乱序/失败降级可以逐用例精确编排。
 */
const previewMock = vi.fn();

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
    billingDetails,
  }: {
    onReady: (h: {
      confirmPayment: (secret: string) => Promise<{ error?: string }>;
      validate: () => boolean;
    }) => void;
    /** PRD-20260919-checkout-billing-details-passthrough AC-003：页面投影的账单地址 */
    billingDetails?: { address?: Record<string, string> } | null;
  }) => {
    onReady({
      confirmPayment: (secret: string) => confirmMock(secret),
      validate: () => validateMock(),
    });
    return (
      <>
        <div data-testid="card-payment-form" />
        <div data-testid="card-billing-probe">
          {billingDetails?.address
            ? [
                billingDetails.address.line1,
                billingDetails.address.city,
                billingDetails.address.postal_code,
                billingDetails.address.country,
              ].join("|")
            : "none"}
        </div>
      </>
    );
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
    item_count: 2,
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

/**
 * PRD-20260919-checkout-remove-items-block-mobile-summary-meta AC-003：
 * 读取 `CheckoutContext` 发布的摘要元数据（移动端折叠按钮的数据源）。
 */
function SummaryMetaProbe() {
  const { summaryMeta } = useCheckout();
  return (
    <div data-testid="summary-meta-probe">
      {summaryMeta
        ? `${summaryMeta.itemCount}|${summaryMeta.displayTotal}`
        : "none"}
    </div>
  );
}

function renderCheckout(
  cart: ShoppingCart = makeCart(),
  country: string | null = null,
) {
  return render(
    <CheckoutProvider>
      <UnifiedCheckout
        cart={cart}
        shippingMethods={shippingMethods}
        countries={[]}
        isAuthenticated={false}
        country={country}
      />
      <CheckoutSummary />
      <SummaryMetaProbe />
    </CheckoutProvider>,
  );
}

// 本文件渲染最完整的 checkout 树（含 next/dynamic 钱包片段）+ 大量 userEvent 交互：
// 全量套件并行跑 jsdom 时，单个用例超过 vitest 默认 5s 会**随机**超时（与断言无关的假红）。
// 因此整块给足预算；断言本身不做任何放宽。
describe("UnifiedCheckout (PRD-20260830-checkout AC-001/AC-002)", {
  timeout: 20000,
}, () => {
  beforeEach(() => {
    pushMock.mockReset();
    replaceMock.mockReset();
    fetchMock.mockReset();
    previewMock.mockReset();
    stripeConfiguredState.value = false;
    capturedExpressProps = {};
    // PRD-20260914-checkout-quote-confirmation-loop：报价快照存 sessionStorage，
    // 用例间必须隔离，否则快照会泄漏到其它用例的载荷断言。
    sessionStorage.clear();
    // PRD-20260919-shipping-checkout-quote-preview：预览默认「金额不可用」
    // （全部 null）—— 保持「提交时计算」的既有口径；需要预估金额的用例自行覆写。
    previewMock.mockImplementation(async () => ({
      ok: true,
      json: async () => ({
        cart_id: "cart_1",
        currency: "USD",
        delivery_total: null,
        display_delivery_total: null,
        tax_total: null,
        display_tax_total: null,
        discount_total: null,
        display_discount_total: null,
        amount_due: null,
        display_amount_due: null,
        selected_method_id: null,
        methods: [],
        estimated: true,
        address_complete: false,
      }),
    }));
    vi.stubGlobal("fetch", (input: RequestInfo | URL, init?: RequestInit) =>
      input === "/api/checkout/preview"
        ? previewMock(input, init)
        : fetchMock(input, init),
    );
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

  // PRD-20260919-checkout-remove-items-block-mobile-summary-meta AC-003：
  // 结账页向 `CheckoutContext` 发布折叠态元数据（件数 + 金额），
  // 供移动端 order summary 折叠按钮渲染「N items · $X」。
  it("publishes summary meta for the mobile order-summary toggle", () => {
    renderCheckout();

    expect(screen.getByTestId("summary-meta-probe").textContent).toBe(
      "2|$19.98",
    );
  });

  // PRD-20260919-checkout-order-summary-fee-read-model
  // AC-001 / AC-002 / AC-003 / AC-004：无权威报价时的费用口径。
  // ① 运费不再是整句占位（值为短标签）；② 抵扣意图行加载即渲染（旧实现刷新后消失）；
  // ③ 总额标注为预估而非拿小计冒充；④ 明示「金额在提交时确定」。
  it("labels not-yet-computed fees and keeps applied-intent rows visible", () => {
    renderCheckout(
      makeCart({
        discount_code: "SAVE10",
        gift_card: { code: "GC-1", display_amount_remaining: "$5.00" },
      }),
    );

    const summary = screen.getByTestId("unified-order-summary");
    expect(within(summary).getByText("estimatedTotal")).toBeTruthy();
    expect(
      within(summary).queryByText("shippingCalculatedAtSubmit"),
    ).toBeNull();
    expect(
      within(summary).getAllByText("calculatedAtSubmit").length,
    ).toBeGreaterThanOrEqual(3);
    expect(within(summary).getByText(/SAVE10/)).toBeTruthy();
    expect(within(summary).getByText(/GC-1/)).toBeTruthy();
    expect(within(summary).getByText("feesCalculatedAtSubmit")).toBeTruthy();
  });

  // AC-006：无任何抵扣意图 → 不渲染折扣/礼品卡行（不虚构 0 元行）。
  it("omits discount and gift-card rows without intent", () => {
    renderCheckout();

    const summary = screen.getByTestId("unified-order-summary");
    expect(within(summary).getByText("estimatedTotal")).toBeTruthy();
    expect(within(summary).queryByText("discount")).toBeNull();
    expect(within(summary).queryByText("giftCard")).toBeNull();
  });

  // PRD-20260914-checkout-placeholder-controls-governance AC-001
  it("renders numbered sections, marketing opt-in and order summary; hides backend-less placeholders", () => {
    renderCheckout();

    expect(screen.getByText("orderConfirmation")).toBeTruthy();
    expect(screen.getByText("contactInformation")).toBeTruthy();
    expect(screen.getByText("shippingAddress")).toBeTruthy();
    expect(screen.getByText("shippingMethod")).toBeTruthy();
    expect(screen.getByText("paymentMethod")).toBeTruthy();
    expect(screen.getByText("orderSummary")).toBeTruthy();
    expect(screen.getByTestId("unified-order-summary")).toBeInTheDocument();
    // PRD-20260919-checkout-remove-items-block-mobile-summary-meta AC-001：
    // 左栏重复的 Items 区块已删除（页面上不再有 items 标题）。
    expect(screen.queryByText("items")).toBeNull();
    // AC-002：商品明细只保留在右栏订单摘要一处（删除前为左栏 + 右栏两处）。
    expect(screen.getAllByText("Awesome Product")).toHaveLength(1);
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
    // ⚠️ 动态导入 + 全量套件并行时，默认 1s 等待会随机爆掉（与本用例断言无关的假红）→ 显式给足预算。
    await screen.findByTestId(
      "express-checkout-element",
      {},
      { timeout: 10000 },
    );
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

    // ② 自动回落卡支付：卡表单回来，空盒子不再存在；且**不**出现无意义的「Processing...」
    await waitFor(
      () => expect(screen.getByTestId("card-payment-form")).toBeInTheDocument(),
      { timeout: 10000 },
    );
    expect(screen.queryByTestId("express-checkout-element")).toBeNull();
    expect(screen.queryByText("processing")).toBeNull();
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

  // PRD-20260919-payments-checkout-top-express-pay-locale AC-001：
  // 顶部快捷支付区位于 H1 之下、第 1 节（Contact Information 的邮箱输入）之前。
  it("renders the top express area before the contact section (AC-001)", async () => {
    // 未配置 Stripe 时顶部区按 FR-007 静默隐藏，因此这里需要已配置。
    stripeConfiguredState.value = true;
    const cart = makeCart({
      currency: "USD",
      payment_methods: [
        {
          id: "pm_stripe",
          name: "Stripe",
          type: "stripe",
          session_required: true,
          kind: "gateway",
          frontend_kind: "inline",
          option_id: "pm_stripe:card",
          method_key: "card",
          display_name: "Card",
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

    const top = await screen.findByTestId(
      "top-express-payment",
      {},
      { timeout: 10000 },
    );
    const email = screen.getByLabelText("email");
    expect(
      top.compareDocumentPosition(email) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  // PRD-20260919-payments-checkout-top-express-pay-locale AC-002 AC-009：
  // 无 express 入口（默认 cart 仅 inline）→ 顶部区不渲染；第 5 节照常。
  it("does not render the top express area without express entries (AC-002)", () => {
    renderCheckout();

    expect(screen.queryByTestId("top-express-payment")).toBeNull();
    expect(screen.getByText("paymentMethod")).toBeTruthy();
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
  // PRD-20260919-checkout-remove-shipping-change-placeholder-banner AC-001/AC-002：
  // 恒显的「配送选项已变化」占位提示已删除（后端从无该信号）；
  // 真实运费漂移由顶部 `checkout-quote-diff` 横幅表达（见本文件其它用例）。
  it("hides the SMS opt-in placeholder and no longer renders the shipping options-changed placeholder", () => {
    renderCheckout();

    expect(screen.queryByTestId("sms-opt-in")).toBeNull();
    expect(screen.queryByTestId("shipping-options-changed")).toBeNull();
    expect(screen.getByText("shippingMethod")).toBeTruthy();
    expect(screen.getByText("Standard")).toBeTruthy();
  });

  // PRD-20260919-checkout-billing-details-passthrough AC-003：
  // 页面把「同配送 / 自定义」的账单地址投影给卡表单（与确认区回显同源），
  // 卡支付随卡把该地址送到 Stripe PaymentMethod。
  it("projects the selected billing address into the card form (FR-003)", async () => {
    const user = userEvent.setup();
    renderCheckout();

    // ① 默认「同配送」→ 投影 = 配送地址
    await fillRequiredFields(user);
    expect(screen.getByTestId("card-billing-probe").textContent).toBe(
      "12 Analytical Way|London|SW1A 1AA|GB",
    );

    // ② 取消勾选并填写自定义账单地址 → 投影切换为该地址
    await user.click(screen.getByTestId("billing-use-shipping"));
    await user.type(screen.getByLabelText("bill-first_name"), "Grace");
    await user.type(screen.getByLabelText("bill-last_name"), "Hopper");
    await user.type(screen.getByLabelText("bill-address1"), "1 Billing St");
    await user.type(screen.getByLabelText("bill-city"), "Billingville");
    await user.type(screen.getByLabelText("bill-postal_code"), "EC1A 1BB");
    await user.type(screen.getByLabelText("bill-country_iso"), "GB");
    await user.type(screen.getByLabelText("bill-state_abbr"), "LDN");

    expect(screen.getByTestId("card-billing-probe").textContent).toBe(
      "1 Billing St|Billingville|EC1A 1BB|GB",
    );
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

  // PRD-20260919-checkout-payment-billing-and-card-form-polish AC-002 / AC-003：
  // 账单区块对所有支付方式可见 + 带语境标题（旧行为：只在卡支付盒子内 + 无标题，
  // 未勾选时用户只看到一个裸表单 → 不知道这是什么）。
  it("shows the billing block with a heading and toggles the form via same-as-shipping (FR-002/FR-003)", async () => {
    const user = userEvent.setup();
    renderCheckout();

    // 默认勾选 "Same as shipping address"，只显示标题 + 勾选项，不展开表单
    const block = screen.getByTestId("billing-block");
    expect(block).toBeInTheDocument();
    expect(within(block).getByText("billingAddress")).toBeTruthy();
    const billingCheckbox = within(block).getByTestId("billing-use-shipping");
    // data-testid 挂在 <label> 上（点击目标），勾选状态读真正的控件（radix Checkbox → role=checkbox）
    expect(within(block).getByRole("checkbox")).toBeChecked();
    expect(screen.queryByLabelText("bill-first_name")).toBeNull();

    // 取消勾选 → 展开账单地址表单（标题不再重复出现，控件可访问）
    await user.click(billingCheckbox);
    expect(screen.getByLabelText("bill-first_name")).toBeInTheDocument();
    expect(screen.getByLabelText("bill-address1")).toBeInTheDocument();
    expect(
      within(screen.getByTestId("billing-block")).getAllByText("billingAddress")
        .length,
    ).toBeGreaterThan(0);
  });

  // PRD-20260919-checkout-payment-billing-and-card-form-polish AC-002：
  // 钱包（express）支付不由用户提供账单地址 → 区块只说明来源，
  // 不给一个永远无效的 "Same as shipping address" 勾选框。
  it("replaces the billing checkbox with a wallet hint when a wallet entry is selected (FR-002)", async () => {
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

    // 卡支付选中时仍是勾选框
    expect(screen.getByTestId("billing-use-shipping")).toBeInTheDocument();
    expect(screen.queryByTestId("billing-wallet-hint")).toBeNull();

    await user.click(screen.getByText("Apple Pay"));
    // 动态 import + 全量套件并行时，钱包片段默认 1s 预算会随机爆掉 → 给足预算。
    await screen.findByTestId(
      "express-checkout-element",
      {},
      { timeout: 10000 },
    );

    expect(screen.getByTestId("billing-wallet-hint")).toHaveTextContent(
      "billingFromWallet",
    );
    expect(screen.queryByTestId("billing-use-shipping")).toBeNull();
    // 标题仍在（语境不依赖支付方式）
    expect(
      within(screen.getByTestId("billing-block")).getByText("billingAddress"),
    ).toBeTruthy();
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
    // PRD-20260919-checkout-payment-billing-and-card-form-polish AC-004：
    // 默认「同配送」→ 确认区回显与区块控件同源（而不是静默空白）。
    expect(screen.getByTestId("quote-billing")).toHaveTextContent(
      "sameAsShipping",
    );
    // PRD-20260919-checkout-order-summary-fee-read-model AC-005：
    // 同一份权威报价同步进右栏摘要（与确认区同源同值）。
    const summary = screen.getByTestId("unified-order-summary");
    expect(within(summary).getByText("totalDue")).toBeTruthy();
    expect(within(summary).getByText("$31.98")).toBeTruthy();
    expect(within(summary).getByText("$9.00")).toBeTruthy();
    expect(within(summary).queryByText("estimatedTotal")).toBeNull();
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

  // PRD-20260919-checkout-payment-billing-and-card-form-polish AC-004：
  // 取消「同配送」+ 填写账单地址 → 确认区回显拼接摘要（而不是写死文案）；
  // 字段不全时显式提示，不让用户带着一个看不出内容的订单去付款。
  it("echoes the custom billing address summary in the confirm area (AC-004)", async () => {
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

    // ① 取消同配送 → 填写完整账单地址（服务端/前台都拦截不完整地址）
    await user.click(screen.getByTestId("billing-use-shipping"));
    await user.type(screen.getByLabelText("bill-first_name"), "Grace");
    await user.type(screen.getByLabelText("bill-last_name"), "Hopper");
    await user.type(screen.getByLabelText("bill-address1"), "1 Billing St");
    await user.type(screen.getByLabelText("bill-city"), "Billingville");
    await user.type(screen.getByLabelText("bill-postal_code"), "EC1A 1BB");
    await user.type(screen.getByLabelText("bill-country_iso"), "GB");
    await user.type(screen.getByLabelText("bill-state_abbr"), "LDN");

    await user.click(screen.getByRole("button", { name: "payNow" }));

    // ② 确认区回显拼接摘要（按 address1 / city / postal_code / country 顺序，
    //    空字段不参与拼接，不依赖语序）
    expect(await screen.findByTestId("quote-billing")).toHaveTextContent(
      "1 Billing St, Billingville, EC1A 1BB, GB",
    );
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

  // PRD-20260919-shipping-checkout-quote-preview AC-004 / AC-006：
  // 首屏只读预览 → 右栏显示**预估金额**（不再写「提交时计算」），且默认选中
  // 由**服务端**决定（`selected_method_id` = 管道最便宜口径）。
  it("shows estimated fees from the server preview and adopts the server default method", async () => {
    previewMock.mockImplementation(async () => ({
      ok: true,
      json: async () => ({
        cart_id: "cart_1",
        currency: "USD",
        delivery_total: "5.0",
        display_delivery_total: "$5.00",
        tax_total: "1.6",
        display_tax_total: "$1.60",
        discount_total: null,
        display_discount_total: null,
        amount_due: "26.58",
        display_amount_due: "$26.58",
        selected_method_id: "dm_1",
        methods: [
          {
            id: "dm_1",
            name: "Standard",
            cost: "5.0",
            display_cost: "$5.00",
            reason: null,
            selected: true,
          },
        ],
        estimated: true,
        provisional_country: "US",
        address_complete: false,
      }),
    }));

    renderCheckout(makeCart(), "US");

    const summary = screen.getByTestId("unified-order-summary");
    // 金额落地（预估口径标签 + 金额本身）
    await waitFor(() =>
      expect(within(summary).getByText("estimatedShipping")).toBeTruthy(),
    );
    expect(within(summary).getByText("$5.00")).toBeTruthy();
    expect(within(summary).getByText("$1.60")).toBeTruthy();
    expect(within(summary).getByText("$26.58")).toBeTruthy();
    // 服务端默认选中被采纳（表单不再空选）
    await waitFor(() =>
      expect(screen.getByRole("radio", { name: /Standard/ })).toBeChecked(),
    );
  });

  // AC-006：地址/方式变更 → 改后重取（防抖）；乱序响应不覆盖较新结果。
  it("debounces preview refreshes and discards stale responses", async () => {
    let previewCalls = 0;
    const resolvers: Array<(payload: unknown) => void> = [];
    previewMock.mockImplementation(
      async () =>
        // 第一次响应故意挂起（模拟慢请求）→ 由后续更快响应先落地
        new Promise((resolve) => {
          previewCalls += 1;
          resolvers.push((payload: unknown) =>
            resolve({ ok: true, json: async () => payload }),
          );
        }),
    );

    const user = userEvent.setup();
    renderCheckout(makeCart(), "US");
    await waitFor(() => expect(previewCalls).toBeGreaterThanOrEqual(1));

    // 连续输入 6 个字符（远快于 400ms 防抖窗口）→ 不应产生 6 次请求
    await user.type(screen.getByLabelText("unified-country_iso"), "US1234");
    await waitFor(() => expect(previewCalls).toBeGreaterThan(1), {
      timeout: 3000,
    });
    expect(previewCalls).toBeLessThanOrEqual(3);

    // 乱序落地：先让**较旧**的请求成功（应被丢弃），再让较新的成功
    const first = resolvers[0];
    const last = resolvers[resolvers.length - 1];
    last({
      display_delivery_total: "$9.99",
      display_amount_due: "$29.97",
      methods: [],
      selected_method_id: null,
    });
    first({
      display_delivery_total: "$1.11",
      display_amount_due: "$21.09",
      methods: [],
      selected_method_id: null,
    });

    const summary = screen.getByTestId("unified-order-summary");
    await waitFor(() =>
      expect(within(summary).getByText("$9.99")).toBeTruthy(),
    );
    expect(within(summary).queryByText("$1.11")).toBeNull();
  });

  // AC-006：预览接口失败 → 诚实回落（保留「提交时计算」，绝不显示 0/旧值冒充）。
  it("falls back to the pending label when the preview request fails", async () => {
    previewMock.mockImplementation(async () => ({
      ok: false,
      status: 502,
      json: async () => ({}),
    }));

    renderCheckout(makeCart(), "US");

    const summary = screen.getByTestId("unified-order-summary");
    await waitFor(() =>
      expect(
        within(summary).getAllByText("calculatedAtSubmit").length,
      ).toBeGreaterThanOrEqual(2),
    );
    expect(within(summary).queryByText("$0.00")).toBeNull();
  });

  // PRD-20260919-shipping-checkout-quote-preview AC-005：
  // 预览说某个方式当前算不出费率（缺州/邮编、或该国家不在 zone 内）→ 行内照实写
  // 「填地址后显示」，而不是拿静态估价冒充、也不把方式藏掉。
  it("shows the address-needed hint for methods the preview cannot price", async () => {
    previewMock.mockImplementation(async () => ({
      ok: true,
      json: async () => ({
        cart_id: "cart_1",
        currency: "USD",
        delivery_total: null,
        display_delivery_total: null,
        tax_total: null,
        display_tax_total: null,
        amount_due: null,
        display_amount_due: null,
        selected_method_id: "dm_1",
        methods: [
          {
            id: "dm_1",
            name: "Standard",
            cost: null,
            display_cost: null,
            reason: "address_required",
            selected: false,
          },
        ],
        estimated: true,
        address_complete: false,
      }),
    }));

    renderCheckout(makeCart(), "DE");

    await waitFor(() =>
      expect(screen.getByTestId("shipping-reason-dm_1").textContent).toBe(
        "methodNeedsAddress",
      ),
    );
    // 静态估价标签不再冒充金额（方式行只在可计价时才显示 display_estimated_price）
    expect(screen.queryByText("$5.00")).toBeNull();
  });
});
