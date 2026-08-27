import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Order } from "@pallastrade/sdk";
import { OrderCombinedPay } from "@/components/account/OrderCombinedPay";

const pushMock = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock }),
  usePathname: () => "/us/en/account/orders",
}));

vi.mock("@/lib/data/payment-combination", () => ({
  createPaymentCombination: vi.fn(),
}));

import { createPaymentCombination } from "@/lib/data/payment-combination";
const mockedCreate = vi.mocked(createPaymentCombination);

function order(overrides: Partial<Order> = {}): Order {
  return {
    id: "order_1",
    number: "R1",
    payment_status: "balance_due",
    is_child: false,
    amount_due: "10.0",
    display_amount_due: "$10.00",
    currency: "USD",
    ...overrides,
  } as Order;
}

describe("OrderCombinedPay", () => {
  beforeEach(() => {
    pushMock.mockReset();
    mockedCreate.mockReset();
  });

  it("renders only payable (balance_due, non-child) orders (P5 AC-007)", () => {
    render(
      <OrderCombinedPay
        orders={[order(), order({ id: "order_2", payment_status: "paid" })]}
        basePath="/us/en"
        defaultPaymentMethodId="pm_1"
      />,
    );

    expect(screen.getByText("#R1")).toBeInTheDocument();
    expect(screen.queryByText("#R2")).not.toBeInTheDocument();
  });

  it("creates a combination for selected orders and navigates to checkout (P5 AC-007)", async () => {
    const user = userEvent.setup();
    mockedCreate.mockResolvedValue({
      combination: { id: "pcom_1" },
    } as never);

    render(
      <OrderCombinedPay
        orders={[order()]}
        basePath="/us/en"
        defaultPaymentMethodId="pm_1"
      />,
    );

    await user.click(screen.getByRole("checkbox"));
    await user.click(screen.getByRole("button", { name: "paySelected" }));

    expect(mockedCreate).toHaveBeenCalledWith(["order_1"], "pm_1");
    expect(pushMock).toHaveBeenCalledWith("/us/en/combined-payment/pcom_1");
  });
});
