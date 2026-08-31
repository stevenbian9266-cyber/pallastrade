import type { Order } from "@pallastrade/sdk";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PaymentCheckoutModal } from "@/components/checkout/PaymentCheckoutModal";

const refreshMock = vi.fn();
const onOpenChangeMock = vi.fn();

// 稳定引用：next-intl 的 t 函数在真实环境跨 render 稳定（避免 effect 依赖抖动）
const tFn = (key: string, params?: Record<string, unknown>) =>
  params ? `${key}:${params.number ?? ""}` : key;

vi.mock("next-intl", () => ({
  useTranslations: () => tFn,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: refreshMock, push: vi.fn() }),
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
  extractSessionClientSecret: (
    session: {
      external_data?: Record<string, unknown> | null;
    } | null,
  ) => {
    const raw = session?.external_data?.client_secret as string | undefined;
    return raw ? decodeURIComponent(raw) : null;
  },
}));

const createCombinationMock = vi.fn();
const getCombinationMock = vi.fn();
const completeCombinationMock = vi.fn();

vi.mock("@/lib/data/payment-combination", () => ({
  createPaymentCombination: (...args: unknown[]) =>
    createCombinationMock(...args),
  getPaymentCombination: (...args: unknown[]) => getCombinationMock(...args),
  completeCombinationSession: (...args: unknown[]) =>
    completeCombinationMock(...args),
}));

// StripePaymentForm mock（组合支付）：暴露 confirmPayment 供测试驱动
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
    onReady({
      confirmPayment: (url: string) => confirmMock(url),
    });
    return <div data-testid="stripe-form" data-secret={clientSecret} />;
  },
}));

// CardPaymentForm mock（单笔 Stripe 自绘卡字段）
const cardConfirmMock = vi.fn();
const cardValidateMock = vi.fn().mockReturnValue(true);
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
      confirmPayment: (secret: string) => cardConfirmMock(secret),
      validate: () => cardValidateMock(),
    });
    return <div data-testid="card-payment-form" />;
  },
}));

function order(overrides: Partial<Order> = {}): Order {
  return {
    id: "order_1",
    number: "R1",
    payment_status: "balance_due",
    is_child: false,
    amount_due: "10.0",
    display_amount_due: "$10.00",
    currency: "USD",
    payment_methods: [
      { id: "pm_card", name: "Card", type: "stripe", session_required: true },
    ],
    ...overrides,
  } as Order;
}

describe("PaymentCheckoutModal (PRD-20260830-checkout AC-004/005/006/007)", () => {
  beforeEach(() => {
    refreshMock.mockReset();
    onOpenChangeMock.mockReset();
    createOrderSessionMock.mockReset();
    completeOrderSessionMock.mockReset();
    completeOrderMock.mockReset();
    createCombinationMock.mockReset();
    getCombinationMock.mockReset();
    completeCombinationMock.mockReset();
    confirmMock.mockReset();
    cardConfirmMock.mockReset();
    cardValidateMock.mockReset();
    cardValidateMock.mockReturnValue(true);
    createOrderSessionMock.mockResolvedValue({
      success: true,
      session: { id: "ps_1", external_data: { client_secret: "sec_1" } },
    });
    completeOrderSessionMock.mockResolvedValue({ success: true });
    completeOrderMock.mockResolvedValue({ success: true, order: {} });
    confirmMock.mockResolvedValue({});
    cardConfirmMock.mockResolvedValue({});
  });

  it("renders amount due + payment method radio + self-drawn card form for a single order (AC-004/005)", async () => {
    render(
      <PaymentCheckoutModal
        open
        onOpenChange={onOpenChangeMock}
        orders={[order()]}
        basePath="/us/en"
      />,
    );

    expect(screen.getByText("amountDue")).toBeTruthy();
    expect(screen.getByText("$10.00")).toBeTruthy();
    expect(screen.getByText("Card")).toBeTruthy();

    // PRD-20260831-payments-stripe-自绘卡支付表单：单笔 Stripe 表单始终渲染，
    // 且不预创建 session（避免提前转换 cart）
    await waitFor(() =>
      expect(screen.getByTestId("card-payment-form")).toBeInTheDocument(),
    );
    expect(createOrderSessionMock).not.toHaveBeenCalled();
  });

  it("pays a single order: Pay Now creates PaymentIntent session → confirm card → complete (AC-005)", async () => {
    const user = userEvent.setup();
    render(
      <PaymentCheckoutModal
        open
        onOpenChange={onOpenChangeMock}
        orders={[order()]}
        basePath="/us/en"
      />,
    );

    await waitFor(() =>
      expect(screen.getByTestId("card-payment-form")).toBeInTheDocument(),
    );

    await user.click(screen.getByRole("button", { name: "payNow" }));

    // 创建 PaymentIntent 会话（mode: payment_intent）→ confirmCardPayment
    await waitFor(() =>
      expect(createOrderSessionMock).toHaveBeenCalledWith(
        "order_1",
        "pm_card",
        undefined,
        "payment_intent",
      ),
    );
    await waitFor(() => expect(cardConfirmMock).toHaveBeenCalledWith("sec_1"));
    await waitFor(() =>
      expect(completeOrderSessionMock).toHaveBeenCalledWith("order_1", "ps_1"),
    );
    await waitFor(() =>
      expect(completeOrderMock).toHaveBeenCalledWith("order_1"),
    );
    // 成功 → 关闭弹窗 + 刷新
    await waitFor(() => expect(onOpenChangeMock).toHaveBeenCalledWith(false));
    expect(refreshMock).toHaveBeenCalled();
  });

  it("combines multiple orders: creates combination, shows breakdown + total (AC-006)", async () => {
    createCombinationMock.mockResolvedValue({
      success: true,
      combination: { id: "pcom_1" },
    });
    getCombinationMock.mockResolvedValue({
      success: true,
      id: "pcom_1",
      amount: "30.00",
      currency: "USD",
      payment_session: {
        id: "ps_combo",
        order_id: "order_1",
        external_data: { client_secret: "sec_combo" },
      },
      orders: [
        order(),
        order({
          id: "order_2",
          number: "R2",
          display_total: "$20.00",
        }),
      ],
    });

    render(
      <PaymentCheckoutModal
        open
        onOpenChange={onOpenChangeMock}
        orders={[
          order(),
          order({ id: "order_2", number: "R2", display_total: "$20.00" }),
        ]}
        basePath="/us/en"
      />,
    );

    await waitFor(() =>
      expect(createCombinationMock).toHaveBeenCalledWith(
        ["order_1", "order_2"],
        "pm_card",
      ),
    );
    await waitFor(() => expect(screen.getByText("30.00 USD")).toBeTruthy());
    // 各单分摊（orderNumber:插值）
    expect(screen.getByText("orderNumber:R1")).toBeTruthy();
    expect(screen.getByText("orderNumber:R2")).toBeTruthy();
    await waitFor(() =>
      expect(screen.getByTestId("stripe-form")).toBeInTheDocument(),
    );
  });

  it("completes a combination payment via completeCombinationSession (AC-006)", async () => {
    createCombinationMock.mockResolvedValue({
      success: true,
      combination: { id: "pcom_1" },
    });
    getCombinationMock.mockResolvedValue({
      success: true,
      id: "pcom_1",
      amount: "30.00",
      currency: "USD",
      payment_session: {
        id: "ps_combo",
        order_id: "order_1",
        external_data: { client_secret: "sec_combo" },
      },
      orders: [
        order(),
        order({ id: "order_2", number: "R2", display_total: "$20.00" }),
      ],
    });

    const user = userEvent.setup();
    render(
      <PaymentCheckoutModal
        open
        onOpenChange={onOpenChangeMock}
        orders={[
          order(),
          order({ id: "order_2", number: "R2", display_total: "$20.00" }),
        ]}
        basePath="/us/en"
      />,
    );

    await waitFor(() =>
      expect(screen.getByTestId("stripe-form")).toBeInTheDocument(),
    );

    await user.click(screen.getByRole("button", { name: "payNow" }));

    await waitFor(() =>
      expect(completeCombinationMock).toHaveBeenCalledWith(
        "order_1",
        "ps_combo",
      ),
    );
    await waitFor(() => expect(onOpenChangeMock).toHaveBeenCalledWith(false));
    expect(refreshMock).toHaveBeenCalled();
  });

  it("shows a fallback when no payment methods are available (AC-004)", () => {
    render(
      <PaymentCheckoutModal
        open
        onOpenChange={onOpenChangeMock}
        orders={[order({ payment_methods: [] as never })]}
        basePath="/us/en"
      />,
    );

    expect(screen.getByText("noPaymentMethods")).toBeTruthy();
  });
});
