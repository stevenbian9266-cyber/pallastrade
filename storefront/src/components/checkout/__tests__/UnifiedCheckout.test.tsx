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

const updateMock = vi.fn();
const submitMock = vi.fn();

vi.mock("@/lib/data/shopping-cart", () => ({
  updateShoppingCartDetails: (...args: unknown[]) => updateMock(...args),
  submitCartOrder: (...args: unknown[]) => submitMock(...args),
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

// AddressFormFields 简化 mock：渲染全部地址字段输入
vi.mock("@/components/checkout/AddressFormFields", () => ({
  AddressFormFields: ({
    address,
    onChange,
    idPrefix,
  }: {
    address: Record<string, string>;
    onChange: (field: string, value: string) => void;
    idPrefix: string;
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
      />
      <CheckoutSummary />
    </CheckoutProvider>,
  );
}

describe("UnifiedCheckout (PRD-20260830-checkout AC-001/AC-002)", () => {
  beforeEach(() => {
    updateMock.mockReset();
    submitMock.mockReset();
    pushMock.mockReset();
    replaceMock.mockReset();
    createOrderSessionMock.mockReset();
    completeOrderSessionMock.mockReset();
    completeOrderMock.mockReset();
    confirmMock.mockReset();
    updateMock.mockResolvedValue({ success: true });
    submitMock.mockResolvedValue({ id: "or_123" });
    createOrderSessionMock.mockResolvedValue({
      success: true,
      session: { id: "ps_1", external_data: { client_secret: "sec_1" } },
    });
    completeOrderSessionMock.mockResolvedValue({ success: true });
    completeOrderMock.mockResolvedValue({ success: true, order: {} });
    confirmMock.mockResolvedValue({});
  });

  it("renders shipping address, items, delivery method, payment method and order summary", () => {
    renderCheckout();

    expect(screen.getByText("orderConfirmation")).toBeTruthy();
    expect(screen.getByText("shippingAddress")).toBeTruthy();
    expect(screen.getByText("items")).toBeTruthy();
    expect(screen.getByText("deliveryMethod")).toBeTruthy();
    expect(screen.getByText("paymentMethod")).toBeTruthy();
    expect(screen.getByText("orderSummary")).toBeTruthy();
    expect(screen.getByTestId("unified-order-summary")).toBeInTheDocument();
    expect(screen.getByText("Awesome Product")).toBeTruthy();
    expect(screen.getByText("Standard")).toBeTruthy();
    expect(screen.getByText("Card")).toBeTruthy();
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

  it("fills address, clicks Pay Now → submits order → creates PaymentIntent session → confirms payment (AC-002)", async () => {
    const user = userEvent.setup();
    renderCheckout();

    // 1. 表单始终渲染（无需 client_secret / js.stripe.com）
    expect(screen.getByTestId("card-payment-form")).toBeInTheDocument();

    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));

    // 2. 未点 Pay Now 前不自动提交订单 / 不自动创建会话
    expect(submitMock).not.toHaveBeenCalled();
    expect(createOrderSessionMock).not.toHaveBeenCalled();

    // 3. 点 Pay Now → 提交订单 → 创建 PaymentIntent 会话 → confirmCardPayment
    await user.click(screen.getByRole("button", { name: "payNow" }));
    await waitFor(() => expect(updateMock).toHaveBeenCalled());
    await waitFor(() => expect(submitMock).toHaveBeenCalledWith("cart_1"));
    await waitFor(() =>
      expect(createOrderSessionMock).toHaveBeenCalledWith(
        "or_123",
        "pm_card",
        undefined,
        "payment_intent",
      ),
    );
    await waitFor(() => expect(confirmMock).toHaveBeenCalledWith("sec_1"));

    // 4. 完成会话 + 完成订单 → 完成页
    await waitFor(() =>
      expect(completeOrderSessionMock).toHaveBeenCalledWith("or_123", "ps_1"),
    );
    await waitFor(() =>
      expect(completeOrderMock).toHaveBeenCalledWith("or_123"),
    );
    await waitFor(() =>
      expect(pushMock).toHaveBeenCalledWith("/us/en/order-placed/or_123"),
    );
    expect(replaceMock).not.toHaveBeenCalled();
  });

  it("redirects to the or_ payment page when payment fails instead of showing empty cart", async () => {
    const user = userEvent.setup();
    confirmMock.mockResolvedValueOnce({ error: "Card declined" });
    renderCheckout();

    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() => expect(submitMock).toHaveBeenCalledWith("cart_1"));
    await waitFor(() => expect(confirmMock).toHaveBeenCalledWith("sec_1"));
    // 支付失败 → 跳 or_ 支付页可重试，不出现空购物车
    await waitFor(() =>
      expect(replaceMock).toHaveBeenCalledWith(
        "/us/en/checkout/or_123?pm=pm_card",
      ),
    );
    expect(pushMock).not.toHaveBeenCalled();
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

    await waitFor(() => expect(submitMock).toHaveBeenCalledWith("cart_1"));
    await waitFor(() =>
      expect(pushMock).toHaveBeenCalledWith("/us/en/order-placed/or_123"),
    );
    expect(createOrderSessionMock).not.toHaveBeenCalled();
  });

  it("shows a fallback message when no payment methods are available", () => {
    renderCheckout(makeCart({ payment_methods: [] as never }));

    expect(screen.getByText("noPaymentMethods")).toBeTruthy();
  });

  it("does not submit when the cart PATCH fails", async () => {
    const user = userEvent.setup();
    updateMock.mockResolvedValue({ success: false, error: "Invalid address" });

    renderCheckout();

    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    // 自绘卡字段模式：点 Pay Now 才触发提交（PRD-20260831-payments-stripe-自绘卡支付表单）
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() => expect(updateMock).toHaveBeenCalled());
    expect(submitMock).not.toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
  });
});
