import type { Cart } from "@pallastrade/sdk";
import { act, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ExpressCheckoutButton } from "@/components/checkout/ExpressCheckoutButton";

/**
 * 钱包 canonical 接线（PRD-20260915-checkout B4）。
 * 这里断言的是**组件层**的编排顺序与分流，模块层断言见
 * `src/lib/checkout/__tests__/express-canonical.test.ts`。
 */

const tFn = (key: string) => key;
vi.mock("next-intl", () => ({ useTranslations: () => tFn }));

const pushMock = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, refresh: vi.fn(), replace: vi.fn() }),
}));

vi.mock("@/lib/utils/stripe", () => ({
  isStripeConfigured: () => true,
  getStripePromise: () => Promise.resolve(null),
  resolveStripePublishableKey: () => "pk_test_mock",
}));

vi.mock("@/lib/data/express-checkout-flow", () => ({
  expressCheckoutResolveShipping: vi.fn(),
  expressCheckoutSelectRates: vi.fn(),
}));

const confirmPaymentMock = vi.fn();
const elementsSubmitMock = vi.fn().mockResolvedValue({});
const elementsUpdateMock = vi.fn();
const stripeStub = {
  confirmPayment: (...args: unknown[]) => confirmPaymentMock(...args),
};
const elementsStub = {
  submit: () => elementsSubmitMock(),
  update: (opts: unknown) => elementsUpdateMock(opts),
};

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

const fetchMock = vi.fn();
vi.stubGlobal("fetch", fetchMock);

const cart = {
  id: "cart_1",
  currency: "usd",
  payment_methods: [
    { id: "pm_stripe", session_required: true },
    { id: "pm_manual", session_required: false },
  ],
  items: [],
  fulfillments: [],
} as unknown as Cart;

const event = () => ({
  billingDetails: {
    email: "ada@example.com",
    phone: "+15550001111",
    name: "Ada Lovelace",
    address: {
      line1: "1 Analytical Way",
      city: "London",
      postal_code: "E1 6AN",
      country: "GB",
      state: "London",
    },
  },
  shippingAddress: {
    name: "Ada Lovelace",
    address: {
      line1: "1 Analytical Way",
      city: "London",
      postal_code: "E1 6AN",
      country: "GB",
      state: "London",
    },
  },
  paymentFailed: vi.fn(),
  resolve: vi.fn(),
  reject: vi.fn(),
});

function jsonResponse(status: number, body: unknown) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  };
}

async function confirm() {
  const e = event();
  await act(async () => {
    await (capturedElementProps.onConfirm as (ev: unknown) => Promise<void>)(e);
  });
  return e;
}

describe("ExpressCheckoutButton (canonical wallet)", () => {
  beforeEach(() => {
    fetchMock.mockReset();
    pushMock.mockReset();
    confirmPaymentMock.mockReset();
    elementsSubmitMock.mockClear();
    capturedElementProps = {};
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-001 AC-003 AC-004
  it("runs the canonical chain and lands on the unified result page", async () => {
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse(200, {
          order: { id: "or_9" },
          transaction: { id: "txn_9", state: "payment_pending" },
          session: { id: "ps_9", external_data: { client_secret: "cs_9" } },
        }),
      )
      .mockResolvedValueOnce(jsonResponse(200, { order: { id: "or_9" } }));
    confirmPaymentMock.mockResolvedValue({ error: undefined });

    render(
      <ExpressCheckoutButton
        cart={cart}
        basePath="/us/en"
        onComplete={vi.fn()}
      />,
    );
    await waitFor(() => expect(capturedElementProps.onConfirm).toBeDefined());

    const e = await confirm();

    // FR-001：canonical start（BFF），携带会话支付方式
    const [startUrl, startInit] = fetchMock.mock.calls[0] as [
      string,
      RequestInit,
    ];
    expect(startUrl).toBe("/api/checkout/start");
    expect(startInit.method).toBe("POST");
    expect(JSON.parse(String(startInit.body))).toMatchObject({
      cart_id: "cart_1",
      payment_method_id: "pm_stripe",
      payment_mode: "payment_intent",
    });

    // FR-004：return_url = 统一结果页
    const confirmArgs = confirmPaymentMock.mock.calls[0][0] as {
      clientSecret: string;
      confirmParams: { return_url: string };
    };
    expect(confirmArgs.clientSecret).toBe("cs_9");
    expect(confirmArgs.confirmParams.return_url).toBe(
      "http://localhost:3000/us/en/payment-result/or_9?session=ps_9",
    );

    // FR-003：best-effort PATCH 完成（Order 域）
    const [patchUrl, patchInit] = fetchMock.mock.calls[1] as [
      string,
      RequestInit,
    ];
    expect(patchUrl).toBe("/api/checkout/start");
    expect(patchInit.method).toBe("PATCH");
    expect(JSON.parse(String(patchInit.body))).toMatchObject({
      order_id: "or_9",
      session_id: "ps_9",
    });

    expect(pushMock).toHaveBeenCalledWith(
      "http://localhost:3000/us/en/payment-result/or_9?session=ps_9",
    );
    expect(e.paymentFailed).not.toHaveBeenCalled();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-005
  it("sends already-charged recovery cases to the result page instead of retrying", async () => {
    fetchMock.mockResolvedValue(
      jsonResponse(409, {
        error: {
          code: "INVENTORY_RECOVERY_REQUIRED",
          message: "Payment captured, order confirming",
        },
      }),
    );

    render(
      <ExpressCheckoutButton
        cart={cart}
        basePath="/us/en"
        onComplete={vi.fn()}
      />,
    );
    await waitFor(() => expect(capturedElementProps.onConfirm).toBeDefined());

    const e = await confirm();

    expect(confirmPaymentMock).not.toHaveBeenCalled();
    expect(e.paymentFailed).not.toHaveBeenCalled();
    expect(pushMock).toHaveBeenCalledWith(
      "http://localhost:3000/us/en/payment-result/cart_1?notice=recovery",
    );
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-006
  it("keeps the shopper in the drawer when the canonical start is rejected", async () => {
    fetchMock.mockResolvedValue(
      jsonResponse(422, {
        error: {
          code: "INSUFFICIENT_STOCK",
          message: "Product A is sold out",
        },
      }),
    );

    render(
      <ExpressCheckoutButton
        cart={cart}
        basePath="/us/en"
        onComplete={vi.fn()}
      />,
    );
    await waitFor(() => expect(capturedElementProps.onConfirm).toBeDefined());

    const e = await confirm();

    expect(pushMock).not.toHaveBeenCalled();
    expect(confirmPaymentMock).not.toHaveBeenCalled();
    expect(e.paymentFailed).toHaveBeenCalledWith({ reason: "fail" });
    await screen.findByText("Product A is sold out");
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-007
  it("never confirms when the server returned no provider secret", async () => {
    fetchMock.mockResolvedValue(
      jsonResponse(200, {
        order: { id: "or_9" },
        transaction: { id: "txn_9", state: "payment_pending" },
        session: { id: "ps_9", external_data: {} },
      }),
    );

    render(
      <ExpressCheckoutButton
        cart={cart}
        basePath="/us/en"
        onComplete={vi.fn()}
      />,
    );
    await waitFor(() => expect(capturedElementProps.onConfirm).toBeDefined());

    const e = await confirm();

    expect(confirmPaymentMock).not.toHaveBeenCalled();
    expect(pushMock).not.toHaveBeenCalled();
    expect(e.paymentFailed).toHaveBeenCalledWith({ reason: "fail" });
  });

  // PRD-20260918-payments-d7-payment-section-express AC-011：
  // 设备无可用钱包（全 false）→ 显式说明块（旧行为：静默 `return null` → 父级只剩空盒子）
  it("renders an explicit notice when the device has no wallet available (D7 AC-011)", async () => {
    const onAvailabilityChange = vi.fn();
    render(
      <ExpressCheckoutButton
        cart={cart}
        basePath="/us/en"
        onComplete={vi.fn()}
        onAvailabilityChange={onAvailabilityChange}
      />,
    );
    await waitFor(() => expect(capturedElementProps.onReady).toBeDefined());

    await act(async () => {
      (capturedElementProps.onReady as (event: unknown) => void)({
        availablePaymentMethods: {
          applePay: false,
          googlePay: false,
          link: false,
        },
      });
    });

    expect(onAvailabilityChange).toHaveBeenCalledWith({
      state: "unavailable",
      reason: "device",
    });
    const notice = await screen.findByTestId("wallet-unavailable-notice");
    expect(notice.getAttribute("data-reason")).toBe("device");
  });

  // PRD-20260918-payments-d7-payment-section-express AC-011：
  // 元素 iframe 被中断 / 设备无钱包 → `onReady` **永不**触发 → 看门狗超时降级（不留无限加载态）
  it("degrades when the wallet element never reports availability (D7 AC-011)", async () => {
    const onAvailabilityChange = vi.fn();
    render(
      <ExpressCheckoutButton
        cart={cart}
        basePath="/us/en"
        onComplete={vi.fn()}
        onAvailabilityChange={onAvailabilityChange}
      />,
    );
    // 元素已挂载（onReady 已接线），但从未上报设备能力
    expect(capturedElementProps.onReady).toBeDefined();
    expect(screen.queryByTestId("wallet-unavailable-notice")).toBeNull();

    // 等看门狗（WALLET_READY_TIMEOUT_MS）超时 → 显式降级（可重试）
    await waitFor(
      () =>
        expect(screen.getByTestId("wallet-unavailable-notice")).toBeTruthy(),
      { timeout: 14000, interval: 250 },
    );
    expect(onAvailabilityChange).toHaveBeenCalledWith({
      state: "unavailable",
      reason: "timeout",
    });
    // 超时可重试（不是永久判死）：说明块内提供「重试」
    expect(screen.getByTestId("wallet-retry")).toBeTruthy();
  }, 20000);

  // PRD-20260918-payments-d7-payment-section-express AC-012：
  // 可用性**未知**（SDK 未给 availablePaymentMethods）→ 保持渲染，不得当成不可用、不得上报结论
  it("keeps the wallet element when availability data is unknown (D7 AC-012)", async () => {
    const onAvailabilityChange = vi.fn();
    render(
      <ExpressCheckoutButton
        cart={cart}
        basePath="/us/en"
        onComplete={vi.fn()}
        onAvailabilityChange={onAvailabilityChange}
      />,
    );
    await waitFor(() => expect(capturedElementProps.onReady).toBeDefined());

    await act(async () => {
      (capturedElementProps.onReady as (event: unknown) => void)({});
    });

    // 未知 → 保持加载，且**不**给出「可用/不可用」结论（旧行为 fail-open 会导致空按钮区）
    expect(onAvailabilityChange).toHaveBeenLastCalledWith({
      state: "unknown",
    });
    expect(onAvailabilityChange).not.toHaveBeenCalledWith({
      state: "available",
    });
    expect(screen.getByTestId("express-checkout-element")).toBeTruthy();
    expect(screen.queryByTestId("wallet-unavailable-notice")).toBeNull();
  });

  // PRD-20260918-payments-d7-payment-section-express AC-013：
  // **点谁显示谁** —— 选中 Apple Pay 入口 → 元素只启用 Apple Pay（其余 never）
  it("renders only the selected wallet entry (D7 AC-013)", async () => {
    render(
      <ExpressCheckoutButton
        cart={cart}
        basePath="/us/en"
        entryKind="apple_pay"
        onComplete={vi.fn()}
      />,
    );
    await waitFor(() => expect(capturedElementProps.options).toBeDefined());

    expect(
      (
        capturedElementProps.options as {
          paymentMethods: Record<string, string>;
        }
      ).paymentMethods,
    ).toEqual({ applePay: "always", googlePay: "never", link: "never" });
  });

  // AC-013（反例）：无入口上下文（购物车抽屉）→ 多钱包并排（保持既有行为）
  it("keeps every wallet enabled when there is no entry context (D7 AC-013)", async () => {
    render(
      <ExpressCheckoutButton
        cart={cart}
        basePath="/us/en"
        onComplete={vi.fn()}
      />,
    );
    await waitFor(() => expect(capturedElementProps.options).toBeDefined());

    expect(
      (
        capturedElementProps.options as {
          paymentMethods: Record<string, string>;
        }
      ).paymentMethods,
    ).toEqual({ applePay: "always", googlePay: "always", link: "auto" });
  });
});
