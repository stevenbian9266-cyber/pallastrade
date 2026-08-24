import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mockPush = vi.fn();
const mockCreatePaymentGroup = vi.fn();

vi.mock("next-intl", async () => {
  const actual = await vi.importActual("next-intl");
  return {
    ...actual,
    useTranslations: () => (key: string) => key,
  };
});

vi.mock("next/navigation", () => ({
  useRouter: () => ({
    push: mockPush,
    replace: vi.fn(),
    refresh: vi.fn(),
    back: vi.fn(),
    forward: vi.fn(),
    prefetch: vi.fn(),
  }),
}));

vi.mock("@/lib/data/payment-groups", () => ({
  createPaymentGroup: (orderIds: string[]) => mockCreatePaymentGroup(orderIds),
}));

vi.mock("@/components/ui/checkbox", () => ({
  Checkbox: ({
    id,
    checked,
    onCheckedChange,
  }: {
    id: string;
    checked: boolean;
    onCheckedChange: () => void;
  }) => (
    <input
      type="checkbox"
      id={id}
      checked={checked}
      onChange={onCheckedChange}
      data-testid={`checkbox-${id}`}
    />
  ),
}));

import { CombinedPaymentPicker } from "@/components/account/CombinedPaymentPicker";

const unpaidOrders = [
  { id: "or_aaa", number: "R1001", currency: "USD", total: "50.00" },
  { id: "or_bbb", number: "R1002", currency: "USD", total: "30.00" },
] as never[];

describe("CombinedPaymentPicker", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockCreatePaymentGroup.mockResolvedValue({
      success: true,
      group: { id: "pg_123" },
    });
  });

  it("renders unpaid orders with checkboxes", () => {
    render(<CombinedPaymentPicker orders={unpaidOrders} basePath="/us/en" />);
    expect(screen.getByText("#R1001")).toBeTruthy();
    expect(screen.getByText("#R1002")).toBeTruthy();
    expect(screen.getByTestId("combined-pay-button")).toBeTruthy();
  });

  it("disables the pay button until at least one order is selected", () => {
    render(<CombinedPaymentPicker orders={unpaidOrders} basePath="/us/en" />);
    const button = screen.getByTestId(
      "combined-pay-button",
    ) as HTMLButtonElement;
    expect(button.disabled).toBe(true);

    fireEvent.click(screen.getByTestId("checkbox-combined-or_aaa"));
    expect(button.disabled).toBe(false);
  });

  it("creates a payment group and navigates to the combined payment page", async () => {
    render(<CombinedPaymentPicker orders={unpaidOrders} basePath="/us/en" />);

    fireEvent.click(screen.getByTestId("checkbox-combined-or_aaa"));
    fireEvent.click(screen.getByTestId("checkbox-combined-or_bbb"));
    fireEvent.click(screen.getByTestId("combined-pay-button"));

    await waitFor(() => {
      expect(mockCreatePaymentGroup).toHaveBeenCalledWith(["or_aaa", "or_bbb"]);
      expect(mockPush).toHaveBeenCalledWith(
        "/us/en/account/combined-payment/pg_123",
      );
    });
  });

  it("shows an error when group creation fails", async () => {
    mockCreatePaymentGroup.mockResolvedValue({
      success: false,
      error: "combinedPayFailed",
    });

    render(<CombinedPaymentPicker orders={unpaidOrders} basePath="/us/en" />);
    fireEvent.click(screen.getByTestId("checkbox-combined-or_aaa"));
    fireEvent.click(screen.getByTestId("combined-pay-button"));

    await waitFor(() => {
      expect(screen.getByText("combinedPayFailed")).toBeTruthy();
    });
    expect(mockPush).not.toHaveBeenCalled();
  });

  // # PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台 AC-005
  it("pays a single order via its own pay button", async () => {
    render(<CombinedPaymentPicker orders={unpaidOrders} basePath="/us/en" />);

    fireEvent.click(screen.getByTestId("pay-single-or_aaa"));

    await waitFor(() => {
      expect(mockCreatePaymentGroup).toHaveBeenCalledWith(["or_aaa"]);
      expect(mockPush).toHaveBeenCalledWith(
        "/us/en/account/combined-payment/pg_123",
      );
    });
  });

  // # PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台 AC-005
  it("does not submit multiple times while a single-order payment is in flight", async () => {
    render(<CombinedPaymentPicker orders={unpaidOrders} basePath="/us/en" />);

    fireEvent.click(screen.getByTestId("pay-single-or_aaa"));
    fireEvent.click(screen.getByTestId("pay-single-or_aaa"));

    await waitFor(() => {
      expect(mockCreatePaymentGroup).toHaveBeenCalledTimes(1);
    });
  });
});
