import type { Cart } from "@pallastrade/sdk";
import { act, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type {
  PaymentEntry,
  PaymentMethodWithEntries,
} from "@/components/checkout/PaymentSection";
import { TopExpressPay } from "@/components/checkout/TopExpressPay";

/**
 * PRD-20260919-payments-checkout-top-express-pay-locale：
 * 顶部快捷支付区（容器层）——渲染条件、入口集合（服务端投影、零筛选）、
 * 设备不可用整区隐藏、凭据透传。子组件（钱包元素）行为见
 * `ExpressCheckoutButton.test.tsx` 的 "(top express area)" 段。
 */

const tFn = (key: string) => key;
vi.mock("next-intl", () => ({ useTranslations: () => tFn }));

let capturedProps: Record<string, unknown> = {};
vi.mock("@/components/checkout/ExpressCheckoutButton", () => ({
  ExpressCheckoutButton: (props: Record<string, unknown>) => {
    capturedProps = props;
    return <div data-testid="express-checkout-element" />;
  },
}));

const cart = { id: "cart_1", currency: "usd" } as unknown as Cart;

function entry(
  methodKey: string,
  frontendKind: string,
  position: number,
): PaymentEntry {
  return {
    option_id: `pm_stripe:${methodKey}`,
    method_key: methodKey,
    display_name: methodKey,
    frontend_kind: frontendKind,
    group: frontendKind === "express" ? "wallet" : "card",
    position,
  };
}

function stripeMethod(entries: PaymentEntry[]): PaymentMethodWithEntries {
  return {
    id: "pm_stripe",
    name: "Stripe",
    session_required: true,
    kind: "gateway",
    frontend_kind: "inline",
    option_id: "pm_stripe:card",
    method_key: "card",
    display_name: "Card",
    client_config: { publishable: { publishable_key: "pk_test_1" } },
    entries,
  } as unknown as PaymentMethodWithEntries;
}

function renderArea(methods: PaymentMethodWithEntries[]) {
  return render(
    <TopExpressPay
      cart={cart}
      basePath="/us/en"
      methods={methods}
      onComplete={vi.fn()}
    />,
  );
}

describe("TopExpressPay (PRD-20260919-payments-checkout-top-express-pay-locale)", () => {
  beforeEach(() => {
    capturedProps = {};
  });

  // PRD-20260919-payments-checkout-top-express-pay-locale AC-001 AC-003 AC-006
  it("renders the express area for the server express entries", () => {
    renderArea([
      stripeMethod([
        entry("card", "inline", 1),
        entry("apple_pay", "express", 2),
        entry("google_pay", "express", 3),
      ]),
    ]);

    expect(screen.getByTestId("top-express-payment")).toBeTruthy();
    expect(capturedProps.entryKinds).toEqual(["apple_pay", "google_pay"]);
    expect(capturedProps.maxColumns).toBe(2);
    expect(capturedProps.degradedDisplay).toBe("toast");
    expect(capturedProps.clientConfig).toEqual({
      publishable: { publishable_key: "pk_test_1" },
    });
  });

  // PRD-20260919-payments-checkout-top-express-pay-locale AC-002
  it("does not render when there is no express entry", () => {
    renderArea([stripeMethod([entry("card", "inline", 1)])]);

    expect(screen.queryByTestId("top-express-payment")).toBeNull();
  });

  // PRD-20260919-payments-checkout-top-express-pay-locale AC-004：
  // 服务端可能是 express 但 Stripe 元素不承载的 kind（paypal 等）不进入顶部区
  // ——它们仍保留在第 5 节入口列表（客户端不按 kind 隐藏入口）。
  it("skips express kinds the wallet widget cannot render", () => {
    renderArea([
      stripeMethod([
        entry("paypal", "express", 1),
        entry("google_pay", "express", 2),
      ]),
    ]);

    expect(capturedProps.entryKinds).toEqual(["google_pay"]);
  });

  // PRD-20260919-payments-checkout-top-express-pay-locale AC-008：
  // 设备能力确定性不可用 → 整区（含标题/分隔线）隐藏，不留空盒、不给噪音提示。
  it("hides the whole area when the device reports no wallet", async () => {
    renderArea([stripeMethod([entry("apple_pay", "express", 1)])]);
    expect(screen.getByTestId("top-express-payment")).toBeTruthy();

    await act(async () => {
      (capturedProps.onAvailabilityChange as (r: unknown) => void)({
        state: "unavailable",
        reason: "device",
      });
    });

    expect(screen.queryByTestId("top-express-payment")).toBeNull();
  });
});
