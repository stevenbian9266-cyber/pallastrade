import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type {
  PaymentEntry,
  PaymentMethodWithEntries,
} from "@/components/checkout/PaymentSection";
import { WalletPaymentButtons } from "@/components/checkout/WalletPaymentButtons";
import type { WalletAvailability } from "@/lib/checkout/wallet-availability";

/**
 * PALLAS-CUSTOM: D7（PRD-20260918-payments-d7-payment-section-express）—— 钱包快捷支付接线。
 *
 *   AC-007：选择钱包入口 → 创建 **PaymentIntent 模式**会话（带 `option_kind`）→
 *           挂载 ExpressCheckoutElement（client_secret）→ 确认 → 完成会话 → 结果页
 *   AC-008：入口被服务端拒绝（`payment_option_not_available`）→ 通知父级刷新列表，不建会话
 */

const tFn = (key: string) => key;
vi.mock("next-intl", () => ({ useTranslations: () => tFn }));

/** D7 补口 2：可切换「已配置/未配置」以覆盖降级分支。 */
const stripeConfiguredState = vi.hoisted(() => ({ value: true }));

const toastErrorMock = vi.fn();
vi.mock("sonner", () => ({
  toast: { error: (...args: unknown[]) => toastErrorMock(...args) },
}));

const createOrderPaymentSessionMock = vi.fn();
const completeAndRedirectMock = vi.fn();
vi.mock("@/lib/data/order-payment", () => ({
  createOrderPaymentSession: (...args: unknown[]) =>
    createOrderPaymentSessionMock(...args),
  completeOrderPaymentSession: vi.fn(),
  completeOrderPaymentSessionAndRedirectToResult: (...args: unknown[]) =>
    completeAndRedirectMock(...args),
}));

vi.mock("@/lib/utils/stripe", () => ({
  isStripeConfigured: () => stripeConfiguredState.value,
  getStripePromise: () => Promise.resolve(null),
  resolveStripePublishableKey: () => "pk_test_mock",
  normalizeClientSecret: (s: string) => s,
  extractSessionClientSecret: (session: {
    external_data?: Record<string, unknown> | null;
  }) => {
    const raw = session?.external_data?.client_secret as string | undefined;
    return raw ? decodeURIComponent(raw) : null;
  },
}));

const confirmPaymentMock = vi.fn();
const stripeStub = {
  confirmPayment: (...args: unknown[]) => confirmPaymentMock(...args),
};
const elementsStub = { submit: vi.fn().mockResolvedValue({}) };

let capturedElementProps: Record<string, unknown> = {};
vi.mock("@stripe/react-stripe-js", () => ({
  Elements: ({ children }: { children: React.ReactNode }) => children,
  ExpressCheckoutElement: (props: Record<string, unknown>) => {
    capturedElementProps = props;
    return <div data-testid="express-checkout-element" />;
  },
  useStripe: () => stripeStub,
  useElements: () => elementsStub,
}));

const method = {
  id: "pm_stripe",
  name: "Stripe",
  type: "stripe",
  session_required: true,
  client_config: {
    provider: "stripe",
    environment: "live",
    publishable: { publishable_key: "pk_test_mock" },
  },
} as unknown as PaymentMethodWithEntries;

const applePayEntry: PaymentEntry = {
  option_id: "pm_stripe:apple_pay",
  method_key: "apple_pay",
  display_name: "Apple Pay",
  frontend_kind: "express",
  group: "wallet",
  position: 2,
};

function renderWallet(overrides?: {
  onUnavailable?: () => void;
  onAvailabilityChange?: (result: WalletAvailability) => void;
}) {
  return render(
    <WalletPaymentButtons
      orderId="or_1"
      basePath="/us/en"
      method={method}
      entry={applePayEntry}
      onUnavailable={overrides?.onUnavailable}
      onAvailabilityChange={overrides?.onAvailabilityChange}
    />,
  );
}

describe("WalletPaymentButtons (D7)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    stripeConfiguredState.value = true;
    capturedElementProps = {};
    createOrderPaymentSessionMock.mockResolvedValue({
      success: true,
      session: {
        id: "ps_1",
        external_data: { client_secret: "pi_test_abc_secret_xyz%2Fsegment" },
      },
    });
    confirmPaymentMock.mockResolvedValue({});
    completeAndRedirectMock.mockResolvedValue(undefined);
  });

  // PRD-20260918-payments-d7-payment-section-express AC-007：入口（method kind）随会话创建下发，且会话为 PaymentIntent 模式
  it("creates a PaymentIntent session carrying the selected option kind (D7 AC-007)", async () => {
    const user = userEvent.setup();
    renderWallet();

    await user.click(screen.getByTestId("wallet-pay-button"));

    await waitFor(() =>
      expect(createOrderPaymentSessionMock).toHaveBeenCalledWith(
        "or_1",
        "pm_stripe",
        undefined,
        "payment_intent",
        { optionKind: "apple_pay" },
      ),
    );
    // 会话就绪 → 挂载 Stripe 钱包按钮（client_secret 来自服务端）
    expect(await screen.findByTestId("express-checkout-element")).toBeTruthy();
  });

  // AC-007：钱包确认 → confirmPayment（带 client_secret）→ 完成会话并跳结果页
  it("confirms with the session client secret and completes the session (D7 AC-007)", async () => {
    const user = userEvent.setup();
    renderWallet();

    await user.click(screen.getByTestId("wallet-pay-button"));
    await screen.findByTestId("express-checkout-element");

    await act(async () => {
      await (
        capturedElementProps.onConfirm as (event: unknown) => Promise<void>
      )({});
    });

    expect(confirmPaymentMock).toHaveBeenCalledWith(
      expect.objectContaining({
        clientSecret: "pi_test_abc_secret_xyz/segment",
      }),
    );
    await waitFor(() =>
      expect(completeAndRedirectMock).toHaveBeenCalledWith(
        "or_1",
        "ps_1",
        "/us/en",
      ),
    );
  });

  // PRD-20260918-payments-d7-payment-section-express AC-008：入口不可用（服务端拒绝）→ 通知父级刷新列表 + 提示重选，不挂载钱包按钮
  it("notifies the parent and skips the wallet element when the option kind is rejected (D7 AC-008)", async () => {
    const user = userEvent.setup();
    const onUnavailable = vi.fn();
    createOrderPaymentSessionMock.mockResolvedValueOnce({
      success: false,
      code: "payment_option_not_available",
      error: "Payment method is not available for this order",
    });

    renderWallet({ onUnavailable });

    await user.click(screen.getByTestId("wallet-pay-button"));

    await waitFor(() => expect(onUnavailable).toHaveBeenCalledTimes(1));
    expect(screen.queryByTestId("express-checkout-element")).toBeNull();
    expect(toastErrorMock).toHaveBeenCalled();
  });

  // AC-007（可用性）：钱包在该设备不可用时，父级可据此回落其它入口
  it("reports wallet availability from the provider element (D7 AC-007)", async () => {
    const user = userEvent.setup();
    const onAvailabilityChange = vi.fn();
    renderWallet({ onAvailabilityChange });

    await user.click(screen.getByTestId("wallet-pay-button"));
    await screen.findByTestId("express-checkout-element");

    await act(async () => {
      (capturedElementProps.onReady as (event: unknown) => void)({
        availablePaymentMethods: { applePay: true, googlePay: false },
      });
    });

    expect(onAvailabilityChange).toHaveBeenCalledWith({ state: "available" });
  });

  // PRD-20260918-payments-d7-payment-section-express AC-013：
  // **点谁显示谁** —— 选中 Apple Pay 入口 → 元素只启用 Apple Pay（其余 never）
  it("renders only the selected wallet entry (D7 AC-013)", async () => {
    const user = userEvent.setup();
    renderWallet();

    await user.click(screen.getByTestId("wallet-pay-button"));
    await screen.findByTestId("express-checkout-element");

    expect(
      (
        capturedElementProps.options as {
          paymentMethods: Record<string, string>;
        }
      ).paymentMethods,
    ).toEqual({ applePay: "always", googlePay: "never", link: "never" });
  });

  // PRD-20260918-payments-d7-payment-section-express AC-011：
  // 本设备无该钱包（SDK 报告 false）→ 显式降级说明 + 上报父级回落（不再留空白）
  it("renders an explicit degradation notice when the device has no wallet (D7 AC-011)", async () => {
    const user = userEvent.setup();
    const onAvailabilityChange = vi.fn();
    renderWallet({ onAvailabilityChange });

    await user.click(screen.getByTestId("wallet-pay-button"));
    await screen.findByTestId("express-checkout-element");

    await act(async () => {
      (capturedElementProps.onReady as (event: unknown) => void)({
        availablePaymentMethods: { applePay: false, googlePay: false },
      });
    });

    expect(onAvailabilityChange).toHaveBeenCalledWith({
      state: "unavailable",
      reason: "device",
    });
    const notice = screen.getByTestId("wallet-unavailable-notice");
    expect(notice.getAttribute("data-reason")).toBe("device");
    expect(screen.queryByTestId("express-checkout-element")).toBeNull();
  });

  // PRD-20260918-payments-d7-payment-section-express AC-011：
  // 会话就绪、元素已挂载但**永不**回传设备能力（iframe 被中断 / 移动网络慢）→ 看门狗超时降级
  it("degrades when the wallet element never reports availability (D7 AC-011)", async () => {
    const user = userEvent.setup();
    const onAvailabilityChange = vi.fn();
    renderWallet({ onAvailabilityChange });

    await user.click(screen.getByTestId("wallet-pay-button"));
    await screen.findByTestId("express-checkout-element");
    expect(screen.queryByTestId("wallet-unavailable-notice")).toBeNull();

    // 等看门狗（WALLET_READY_TIMEOUT_MS）超时 → 显式降级（**可重试**，不判死）
    await waitFor(
      () =>
        expect(screen.getByTestId("wallet-unavailable-notice")).toBeTruthy(),
      { timeout: 14000, interval: 250 },
    );
    expect(onAvailabilityChange).toHaveBeenCalledWith({
      state: "unavailable",
      reason: "timeout",
    });
    expect(screen.getByTestId("wallet-retry")).toBeTruthy();
  }, 20000);

  // PRD-20260918-payments-d7-payment-section-express AC-012：
  // 可用性**未知**（SDK 未给 availablePaymentMethods）→ 不得当作不可用，也不得给结论
  it("keeps the wallet element when availability data is unknown (D7 AC-012)", async () => {
    const user = userEvent.setup();
    const onAvailabilityChange = vi.fn();
    renderWallet({ onAvailabilityChange });

    await user.click(screen.getByTestId("wallet-pay-button"));
    await screen.findByTestId("express-checkout-element");

    await act(async () => {
      (capturedElementProps.onReady as (event: unknown) => void)({});
    });

    // 未知 → 保持渲染，不得给父级「可用/不可用」结论
    expect(onAvailabilityChange).toHaveBeenLastCalledWith({
      state: "unknown",
    });
    expect(onAvailabilityChange).not.toHaveBeenCalledWith({
      state: "available",
    });
    expect(screen.queryByTestId("wallet-unavailable-notice")).toBeNull();
    expect(screen.getByTestId("express-checkout-element")).toBeTruthy();
  });

  // PRD-20260918-payments-d7-payment-section-express AC-011：
  // 未配置下发密钥（且无环境回落）→ 显式说明（旧行为是静默 `return null`）
  it("shows the degradation notice instead of disappearing when Stripe is unconfigured (D7 AC-011)", () => {
    stripeConfiguredState.value = false;
    renderWallet();

    const notice = screen.getByTestId("wallet-unavailable-notice");
    expect(notice.getAttribute("data-reason")).toBe("unconfigured");
    expect(screen.queryByTestId("wallet-pay-button")).toBeNull();
  });
});
