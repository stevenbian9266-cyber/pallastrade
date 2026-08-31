import type { ShoppingCart } from "@pallastrade/sdk";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UnifiedCheckout } from "@/components/checkout/UnifiedCheckout";

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

const confirmMock = vi.fn();
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
    onReady({ confirmPayment: (url: string) => confirmMock(url) });
    return <div data-testid="stripe-form" data-secret={clientSecret} />;
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
      session: { id: "ps_1", client_secret: "sec_1" },
    });
    completeOrderSessionMock.mockResolvedValue({ success: true });
    completeOrderMock.mockResolvedValue({ success: true, order: {} });
    confirmMock.mockResolvedValue({});
  });

  it("renders shipping address, items, delivery method, payment method and order summary", () => {
    render(
      <UnifiedCheckout
        cart={makeCart()}
        shippingMethods={shippingMethods}
        countries={[]}
      />,
    );

    expect(screen.getByText("orderConfirmation")).toBeTruthy();
    expect(screen.getByText("shippingAddress")).toBeTruthy();
    expect(screen.getByText("items")).toBeTruthy();
    expect(screen.getByText("deliveryMethod")).toBeTruthy();
    expect(screen.getByText("paymentMethod")).toBeTruthy();
    expect(screen.getByText("orderSummary")).toBeTruthy();
    expect(screen.getByText("Awesome Product")).toBeTruthy();
    expect(screen.getByText("Standard")).toBeTruthy();
    expect(screen.getByText("Card")).toBeTruthy();
    // 金额在商品行与订单小结各出现一次
    expect(screen.getAllByText("$19.98").length).toBeGreaterThanOrEqual(2);
  });

  it("keeps Pay Now disabled until all required fields are filled", async () => {
    const user = userEvent.setup();
    render(
      <UnifiedCheckout
        cart={makeCart()}
        shippingMethods={shippingMethods}
        countries={[]}
      />,
    );

    const payNow = screen.getByRole("button", { name: "payNow" });
    expect(payNow).toBeDisabled();

    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    // 物流方式 radio 选中
    await user.click(screen.getByRole("radio", { name: /Standard/ }));

    await waitFor(() => expect(payNow).toBeEnabled());
  });

  it("submits then shows Stripe form in-page and confirms payment (AC-002)", async () => {
    const user = userEvent.setup();
    render(
      <UnifiedCheckout
        cart={makeCart()}
        shippingMethods={shippingMethods}
        countries={[]}
      />,
    );

    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    // 1. PATCH cart + submit 订单
    await waitFor(() => {
      expect(updateMock).toHaveBeenCalledWith(
        "cart_1",
        expect.objectContaining({ email: "ada@example.com" }),
      );
    });
    await waitFor(() => expect(submitMock).toHaveBeenCalledWith("cart_1"));
    // 2. 创建订单支付会话 → 同页渲染 Stripe 表单（不跳转）
    await waitFor(() =>
      expect(createOrderSessionMock).toHaveBeenCalledWith("or_123", "pm_card"),
    );
    await waitFor(() =>
      expect(screen.getByTestId("stripe-form")).toBeInTheDocument(),
    );
    expect(replaceMock).not.toHaveBeenCalled();

    // 3. 按钮变为确认支付 → 点击 → 完成会话 + 完成订单 → 完成页
    await user.click(screen.getByRole("button", { name: "confirmPayment" }));
    await waitFor(() =>
      expect(completeOrderSessionMock).toHaveBeenCalledWith("or_123", "ps_1"),
    );
    await waitFor(() =>
      expect(completeOrderMock).toHaveBeenCalledWith("or_123"),
    );
    await waitFor(() =>
      expect(pushMock).toHaveBeenCalledWith("/us/en/order-placed/or_123"),
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
    render(
      <UnifiedCheckout
        cart={cart}
        shippingMethods={shippingMethods}
        countries={[]}
      />,
    );

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
    render(
      <UnifiedCheckout
        cart={makeCart({ payment_methods: [] as never })}
        shippingMethods={shippingMethods}
        countries={[]}
      />,
    );

    expect(screen.getByText("noPaymentMethods")).toBeTruthy();
  });

  it("does not submit when the cart PATCH fails", async () => {
    const user = userEvent.setup();
    updateMock.mockResolvedValue({ success: false, error: "Invalid address" });

    render(
      <UnifiedCheckout
        cart={makeCart()}
        shippingMethods={shippingMethods}
        countries={[]}
      />,
    );

    await fillRequiredFields(user);
    await user.type(screen.getByLabelText("email"), "ada@example.com");
    await user.click(screen.getByRole("radio", { name: /Standard/ }));
    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() => expect(updateMock).toHaveBeenCalled());
    expect(submitMock).not.toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
  });
});
