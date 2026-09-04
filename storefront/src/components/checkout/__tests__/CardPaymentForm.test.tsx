import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  CardPaymentForm,
  type CardPaymentFormHandle,
} from "@/components/checkout/CardPaymentForm";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

const confirmCardPaymentMock = vi.fn();
const cardElementMock = { __type: "card-number-element" };

// Mock Stripe 经典 Elements 模式（CardNumber/CardExpiry/CardCvc）
vi.mock("@stripe/react-stripe-js", () => ({
  Elements: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  useStripe: () => ({
    confirmCardPayment: (...args: unknown[]) => confirmCardPaymentMock(...args),
  }),
  useElements: () => ({
    getElement: () => cardElementMock,
  }),
  CardNumberElement: (props: {
    onChange?: (e: { complete: boolean }) => void;
  }) => (
    <input
      data-testid="card-number-input"
      onChange={(e) =>
        props.onChange?.({ complete: e.target.value.length > 10 })
      }
    />
  ),
  CardExpiryElement: (props: {
    onChange?: (e: { complete: boolean }) => void;
  }) => (
    <input
      data-testid="card-expiry-input"
      onChange={(e) =>
        props.onChange?.({ complete: e.target.value.length > 3 })
      }
    />
  ),
  CardCvcElement: (props: {
    onChange?: (e: { complete: boolean }) => void;
  }) => (
    <input
      data-testid="card-cvc-input"
      onChange={(e) =>
        props.onChange?.({ complete: e.target.value.length >= 3 })
      }
    />
  ),
}));

vi.mock("@/components/ui/input", () => ({
  Input: (props: Record<string, unknown>) => <input {...(props as object)} />,
}));

let handle: CardPaymentFormHandle | null = null;

function renderForm() {
  return render(<CardPaymentForm onReady={(h) => (handle = h)} />);
}

describe("CardPaymentForm (PRD-20260831-payments-stripe-自绘卡支付表单 AC-005)", () => {
  beforeEach(() => {
    handle = null;
    confirmCardPaymentMock.mockReset();
    confirmCardPaymentMock.mockResolvedValue({ error: undefined });
  });

  it("renders card number / expiry / cvc / name fields immediately (no client_secret needed)", () => {
    renderForm();

    expect(screen.getByTestId("card-payment-form")).toBeInTheDocument();
    expect(screen.getByTestId("card-number-input")).toBeTruthy();
    expect(screen.getByTestId("card-expiry-input")).toBeTruthy();
    expect(screen.getByTestId("card-cvc-input")).toBeTruthy();
    expect(screen.getByTestId("cardholder-name")).toBeTruthy();
  });

  it("rejects incomplete card fields during validation", async () => {
    const user = userEvent.setup();
    renderForm();

    // 未填卡号 → 校验失败
    expect(handle?.validate()).toBe(false);
    await waitFor(() =>
      expect(screen.getByTestId("card-error").textContent).toBe(
        "invalidCardDetails",
      ),
    );

    // 填卡号 + 有效期 + CVC 但缺持卡人姓名 → 仍失败（PRD 3.6 持卡人必填）
    await user.type(
      screen.getByTestId("card-number-input"),
      "4242424242424242",
    );
    await user.type(screen.getByTestId("card-expiry-input"), "12/30");
    await user.type(screen.getByTestId("card-cvc-input"), "123");
    expect(handle?.validate()).toBe(false);
    await waitFor(() =>
      expect(screen.getByTestId("card-error").textContent).toBe(
        "cardholderRequired",
      ),
    );

    // 补上持卡人姓名 → 校验通过
    await user.type(screen.getByTestId("cardholder-name"), "Ada Lovelace");
    expect(handle?.validate()).toBe(true);
  });

  it("confirms the PaymentIntent with the Elements card element on confirmPayment", async () => {
    const user = userEvent.setup();
    renderForm();

    await user.type(
      screen.getByTestId("card-number-input"),
      "4242424242424242",
    );
    await user.type(screen.getByTestId("card-expiry-input"), "12/30");
    await user.type(screen.getByTestId("card-cvc-input"), "123");
    await user.type(screen.getByTestId("cardholder-name"), "Ada Lovelace");

    const result = await handle?.confirmPayment("pi_test_secret_123");
    expect(result).toEqual({});

    // 卡数据经 Elements 加密直传 Stripe（不经过服务器）
    expect(confirmCardPaymentMock).toHaveBeenCalledWith("pi_test_secret_123", {
      payment_method: {
        card: cardElementMock,
        billing_details: { name: "Ada Lovelace" },
      },
    });
  });

  it("surfaces Stripe errors from confirmCardPayment", async () => {
    const user = userEvent.setup();
    renderForm();
    confirmCardPaymentMock.mockResolvedValue({
      error: { message: "Your card was declined." },
    });

    await user.type(
      screen.getByTestId("card-number-input"),
      "4242424242424242",
    );
    await user.type(screen.getByTestId("card-expiry-input"), "12/30");
    await user.type(screen.getByTestId("card-cvc-input"), "123");
    await user.type(screen.getByTestId("cardholder-name"), "Ada Lovelace");

    const result = await handle?.confirmPayment("pi_test_secret_123");
    expect(result).toEqual({ error: "Your card was declined." });
    await waitFor(() =>
      expect(screen.getByTestId("card-error").textContent).toContain(
        "declined",
      ),
    );
  });
});
