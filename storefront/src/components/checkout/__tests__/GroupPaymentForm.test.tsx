import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockReplace = vi.fn();
const mockSearchParams = new Map<string, string>();
const mockCreateGroupPaymentSession = vi.fn();
const mockCompleteGroupPaymentSession = vi.fn();
const mockOnPaid = vi.fn();
const mockOnError = vi.fn();

vi.mock("next-intl", async () => {
  const actual = await vi.importActual("next-intl");
  return {
    ...actual,
    useTranslations: () => (key: string) => key,
  };
});

vi.mock("next/navigation", () => ({
  useRouter: () => ({
    push: vi.fn(),
    replace: mockReplace,
    refresh: vi.fn(),
    back: vi.fn(),
    forward: vi.fn(),
    prefetch: vi.fn(),
  }),
  useSearchParams: () => ({
    get: (key: string) => mockSearchParams.get(key) ?? null,
  }),
}));

vi.mock("@/lib/data/payment-groups", () => ({
  createGroupPaymentSession: (groupId: string, methodId: string) =>
    mockCreateGroupPaymentSession(groupId, methodId),
  completeGroupPaymentSession: (groupId: string, sessionId: string) =>
    mockCompleteGroupPaymentSession(groupId, sessionId),
}));

vi.mock("@/components/checkout/StripePaymentForm", () => ({
  StripePaymentForm: () => <div data-testid="stripe-form" />,
}));

// # PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 AC-013
// 公用收银台：单订单付款与多订单合并支付复用同一 GroupPaymentForm（payment group 语义）
import { GroupPaymentForm } from "@/components/checkout/GroupPaymentForm";

const paymentMethods = [
  {
    id: "pm_cc",
    name: "Credit Card",
    description: "Card",
    type: "card",
    source_required: true,
    session_required: true,
  },
  {
    id: "pm_pp",
    name: "PayPal",
    description: "PayPal",
    type: "paypal",
    source_required: false,
    session_required: false,
  },
];

function renderForm(groupId = "pg_123") {
  return render(
    <GroupPaymentForm
      groupId={groupId}
      basePath="/us/en"
      paymentMethods={paymentMethods}
      onPaid={mockOnPaid}
      onError={mockOnError}
    />,
  );
}

describe("GroupPaymentForm（公用收银台）", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockSearchParams.clear();
    mockCompleteGroupPaymentSession.mockResolvedValue({
      success: true,
      session: { id: "ps_123", status: "completed" },
    });
  });

  it("AC-013: 渲染支付方式列表，未选择时确认按钮禁用", () => {
    renderForm();

    expect(screen.getByText("Credit Card")).toBeTruthy();
    expect(screen.getByText("PayPal")).toBeTruthy();
    const confirm = screen.getByTestId(
      "start-combined-payment",
    ) as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);
  });

  it("AC-013: 选择支付方式 → 创建 session → 显示 Stripe 表单（单订单与合并支付同组件）", async () => {
    mockCreateGroupPaymentSession.mockResolvedValue({
      success: true,
      session: { id: "ps_123", external_data: { client_secret: "cs_123" } },
    });

    renderForm("pg_single"); // 单订单也是 1 订单支付组，走同一收银台组件

    fireEvent.click(screen.getByText("Credit Card"));
    fireEvent.click(screen.getByTestId("start-combined-payment"));

    await waitFor(() => {
      expect(mockCreateGroupPaymentSession).toHaveBeenCalledWith(
        "pg_single",
        "pm_cc",
      );
      expect(screen.getByTestId("stripe-form")).toBeTruthy();
    });
  });

  it("AC-013: Stripe 3DS 回跳（?session=）自动完成支付并上报 onPaid", async () => {
    mockSearchParams.set("session", "ps_3ds");
    mockSearchParams.set("redirect_status", "succeeded");

    renderForm();

    await waitFor(() => {
      expect(mockCompleteGroupPaymentSession).toHaveBeenCalledWith(
        "pg_123",
        "ps_3ds",
      );
    });
    await waitFor(() => {
      expect(mockOnPaid).toHaveBeenCalled();
    });
    expect(mockReplace).toHaveBeenCalledWith(
      "/us/en/account/combined-payment/pg_123",
    );
  });

  it("AC-013: 3DS 回跳失败显示错误且不上报成功", async () => {
    mockSearchParams.set("session", "ps_3ds");
    mockSearchParams.set("redirect_status", "failed");

    renderForm();

    await waitFor(() => {
      expect(screen.getByText("payFailed")).toBeTruthy();
    });
    expect(mockCompleteGroupPaymentSession).not.toHaveBeenCalled();
    expect(mockOnPaid).not.toHaveBeenCalled();
  });
});
