import type { ShoppingCart } from "@pallastrade/sdk";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UnifiedCheckout } from "@/components/checkout/UnifiedCheckout";
import { CheckoutProvider, CheckoutSummary } from "@/contexts/CheckoutContext";

const pushMock = vi.fn();
const replaceMock = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
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
      checkout: { use_shipping: true },
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
                  { id: "pr_1", code: "SAVE5", display_amount: "-$5.00" },
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
});
