import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockReplace = vi.fn();
const mockSearchParams = new Map<string, string>();
const mockGetPaymentGroup = vi.fn();
const mockGetPaymentMethods = vi.fn();
const mockCreateGroupPaymentSession = vi.fn();
const mockCompleteGroupPaymentSession = vi.fn();

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
  getPaymentGroup: (groupId: string) => mockGetPaymentGroup(groupId),
  createGroupPaymentSession: (groupId: string, methodId: string) =>
    mockCreateGroupPaymentSession(groupId, methodId),
  completeGroupPaymentSession: (groupId: string, sessionId: string) =>
    mockCompleteGroupPaymentSession(groupId, sessionId),
}));

vi.mock("@/lib/data/payment-methods", () => ({
  getPaymentMethods: () => mockGetPaymentMethods(),
}));

vi.mock("@/components/checkout/StripePaymentForm", () => ({
  StripePaymentForm: () => <div data-testid="stripe-form" />,
}));

import { CombinedPaymentContent } from "@/components/account/CombinedPaymentContent";

function setSearchParams(params: Record<string, string>) {
  mockSearchParams.clear();
  for (const [k, v] of Object.entries(params)) {
    mockSearchParams.set(k, v);
  }
}

function renderContent() {
  return render(<CombinedPaymentContent groupId="pg_123" basePath="/us/en" />);
}

describe("CombinedPaymentContent", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockSearchParams.clear();
    mockGetPaymentGroup.mockResolvedValue({
      success: true,
      group: {
        id: "pg_123",
        currency: "USD",
        status: "pending",
        orders: [
          {
            id: "or_aaa",
            number: "R1001",
            currency: "USD",
            total: "50.00",
          },
          {
            id: "or_bbb",
            number: "R1002",
            currency: "USD",
            total: "30.00",
          },
        ],
      },
    });
    mockGetPaymentMethods.mockResolvedValue([
      { id: "pm_cc", name: "Credit Card", session_required: true },
      { id: "pm_pp", name: "PayPal", session_required: false },
    ]);
  });

  it("renders the order summary and total", async () => {
    renderContent();
    expect(await screen.findByText("#R1001")).toBeTruthy();
    expect(screen.getByText("#R1002")).toBeTruthy();
    expect(screen.getByText("USD 80.00")).toBeTruthy();
  });

  // # PRD-20260824-checkout-合并支付复用已有支付组继续支付-订单已在支付组时不报错
  // Bug fix 2026-08-24：加载 effect 不得依赖 useTranslations 的 t（引用不稳定会
  // 导致每次重渲染后 effect 重跑 → 无限请求循环）。此处 mock 的 useTranslations
  // 每次渲染返回新函数，正好复现该场景——断言只加载一次。
  it("loads group data exactly once (no infinite request loop)", async () => {
    renderContent();
    await waitFor(() => {
      expect(screen.getByText("#R1001")).toBeTruthy();
    });
    expect(mockGetPaymentGroup).toHaveBeenCalledTimes(1);
    expect(mockGetPaymentMethods).toHaveBeenCalledTimes(1);
  });

  // # 修复：合并支付收银台处理支付组非激活状态（failed/expired 组不再抛状态机裸错误）
  // failed 组显示失败提示，不渲染支付表单/支付方式
  it("shows a failed state for a failed group and hides the payment form", async () => {
    mockGetPaymentGroup.mockResolvedValue({
      success: true,
      group: {
        id: "pg_123",
        currency: "USD",
        status: "failed",
        orders: [
          { id: "or_aaa", number: "R1001", currency: "USD", total: "50.00" },
        ],
      },
    });

    renderContent();

    expect(await screen.findByText("groupFailed")).toBeTruthy();
    expect(screen.getByText("groupFailedDescription")).toBeTruthy();
    expect(screen.queryByTestId("combined-payment-methods")).toBeNull();
    expect(screen.queryByTestId("start-combined-payment")).toBeNull();
  });

  it("shows an ended state for canceled/expired groups", async () => {
    mockGetPaymentGroup.mockResolvedValue({
      success: true,
      group: { id: "pg_123", currency: "USD", status: "expired", orders: [] },
    });

    renderContent();

    expect(await screen.findByText("groupEnded")).toBeTruthy();
    expect(screen.getByText("groupEndedDescription")).toBeTruthy();
  });

  it("shows the success state when the group is already completed", async () => {
    mockGetPaymentGroup.mockResolvedValue({
      success: true,
      group: { id: "pg_123", currency: "USD", status: "completed", orders: [] },
    });

    renderContent();

    expect(await screen.findByText("paymentSuccess")).toBeTruthy();
  });

  // Bug 修复：Stripe 3DS redirect-back 后自动完成支付组，不再停留当前页
  it("auto-completes the payment group on Stripe redirect-back (session param present)", async () => {
    setSearchParams({
      session: "ps_sess123",
      redirect_status: "succeeded",
    });
    mockCompleteGroupPaymentSession.mockResolvedValue({
      success: true,
      session: { id: "ps_sess123", status: "completed" },
    });

    renderContent();

    await waitFor(() => {
      expect(mockCompleteGroupPaymentSession).toHaveBeenCalledWith(
        "pg_123",
        "ps_sess123",
      );
    });

    // 完成后显示成功页并清理 URL 中的 session 参数
    await waitFor(() => {
      expect(screen.getByText("paymentSuccess")).toBeTruthy();
    });
    expect(mockReplace).toHaveBeenCalledWith(
      "/us/en/account/combined-payment/pg_123",
    );
  });

  it("shows an error when redirect-back failed", async () => {
    setSearchParams({
      session: "ps_sess123",
      redirect_status: "failed",
    });

    renderContent();

    await waitFor(() => {
      expect(screen.getByText("payFailed")).toBeTruthy();
    });
    expect(mockCompleteGroupPaymentSession).not.toHaveBeenCalled();
  });

  it("shows an error when completing the redirected session fails", async () => {
    setSearchParams({
      session: "ps_sess123",
      redirect_status: "succeeded",
    });
    mockCompleteGroupPaymentSession.mockResolvedValue({
      success: false,
      error: "completeError",
    });

    renderContent();

    await waitFor(() => {
      expect(screen.getByText("completeError")).toBeTruthy();
    });
    expect(screen.queryByText("paymentSuccess")).toBeNull();
  });

  // # PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台 AC-006
  it("lists payment methods and disables confirm until one is selected", async () => {
    renderContent();

    const methodGroup = await screen.findByTestId("combined-payment-methods");
    expect(methodGroup.textContent).toContain("Credit Card");
    expect(methodGroup.textContent).toContain("PayPal");

    const confirm = screen.getByTestId(
      "start-combined-payment",
    ) as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);
  });

  // # PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台 AC-006
  it("creates a payment session for the selected method and reveals the Stripe form", async () => {
    mockCreateGroupPaymentSession.mockResolvedValue({
      success: true,
      session: {
        id: "ps_123",
        external_data: { client_secret: "cs_123" },
      },
    });
    renderContent();

    await screen.findByTestId("combined-payment-methods");
    fireEvent.click(screen.getByText("Credit Card"));
    fireEvent.click(screen.getByTestId("start-combined-payment"));

    await waitFor(() => {
      expect(mockCreateGroupPaymentSession).toHaveBeenCalledWith(
        "pg_123",
        "pm_cc",
      );
      expect(screen.getByTestId("stripe-form")).toBeTruthy();
    });
  });
});
