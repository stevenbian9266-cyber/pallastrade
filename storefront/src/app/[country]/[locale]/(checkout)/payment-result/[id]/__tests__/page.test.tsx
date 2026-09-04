import type { Order, PaymentSession } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import PaymentResultPage from "@/app/[country]/[locale]/(checkout)/payment-result/[id]/page";

const getOrderMock = vi.fn();
const getSessionMock = vi.fn();
const getCombinationMock = vi.fn();

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => key,
}));

vi.mock("@/lib/data/order-payment", () => ({
  getOrderForCheckout: (...args: unknown[]) => getOrderMock(...args),
  getOrderPaymentSession: (...args: unknown[]) => getSessionMock(...args),
}));

vi.mock("@/lib/data/payment-combination", () => ({
  getPaymentCombination: (...args: unknown[]) => getCombinationMock(...args),
}));

const order = {
  id: "or_1",
  number: "R1",
  state: "pending",
  payment_status: "balance_due",
  display_total: "$10.00",
} as Order;

function renderResult(id = "or_1", session = "ps_1") {
  return PaymentResultPage({
    params: Promise.resolve({ id, country: "us", locale: "en" }),
    searchParams: Promise.resolve({ session }),
  }).then((view) => render(view));
}

describe("PaymentResultPage (PRD-20260830-checkout AC-009)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getOrderMock.mockResolvedValue(order);
    getSessionMock.mockResolvedValue({
      id: "ps_1",
      status: "pending",
    } as PaymentSession);
  });

  it("uses the authoritative paid Order state for success", async () => {
    getOrderMock.mockResolvedValue({ ...order, payment_status: "paid" });

    await renderResult();

    expect(screen.getByRole("heading", { name: "successTitle" })).toBeTruthy();
    expect(screen.queryByText("retryPayment")).toBeNull();
  });

  it("shows failure and retries the same Order", async () => {
    getSessionMock.mockResolvedValue({ id: "ps_1", status: "failed" });

    await renderResult();

    expect(screen.getByRole("heading", { name: "failedTitle" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "retryPayment" })).toHaveAttribute(
      "href",
      "/us/en/checkout/or_1",
    );
  });

  it("shows canceled state from the server session", async () => {
    getSessionMock.mockResolvedValue({ id: "ps_1", status: "canceled" });

    await renderResult();

    expect(screen.getByRole("heading", { name: "canceledTitle" })).toBeTruthy();
  });

  it("shows a pending combination and refreshes the same target", async () => {
    getCombinationMock.mockResolvedValue({
      success: true,
      id: "pcom_1",
      status: "pending",
      amount: "30.00",
      currency: "USD",
    });

    await renderResult("pcom_1", "ps_combo");

    expect(screen.getByRole("heading", { name: "pendingTitle" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "refreshStatus" })).toHaveAttribute(
      "href",
      "/us/en/payment-result/pcom_1?session=ps_combo",
    );
  });
});
