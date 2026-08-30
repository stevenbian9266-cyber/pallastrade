import type { Order } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
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

  // PRD-20260829-checkout AC-001：恰好 1 笔待支付订单 → 单订单 checkout（同 cart）
  it("routes a single selected order to the single-order checkout", async () => {
    const user = userEvent.setup();

    render(
      <OrderCombinedPay
        orders={[order()]}
        basePath="/us/en"
        defaultPaymentMethodId="pm_1"
      />,
    );

    await user.click(screen.getByRole("checkbox"));
    await user.click(screen.getByRole("button", { name: "paySelected" }));

    expect(mockedCreate).not.toHaveBeenCalled();
    expect(pushMock).toHaveBeenCalledWith("/us/en/checkout/order_1");
  });

  // PRD-20260829-checkout AC-002：2+ 笔待支付订单 → 合并支付新流程
  it("creates a combination for multiple selected orders and navigates to the combined flow", async () => {
    const user = userEvent.setup();
    mockedCreate.mockResolvedValue({
      combination: { id: "pcom_1" },
    } as never);

    render(
      <OrderCombinedPay
        orders={[
          order(),
          order({
            id: "order_2",
            number: "R2",
            display_amount_due: "$20.00",
          }),
        ]}
        basePath="/us/en"
        defaultPaymentMethodId="pm_1"
      />,
    );

    await user.click(screen.getAllByRole("checkbox")[0]);
    await user.click(screen.getAllByRole("checkbox")[1]);
    await user.click(screen.getByRole("button", { name: "paySelected" }));

    expect(mockedCreate).toHaveBeenCalledWith(
      ["order_1", "order_2"],
      "pm_1",
    );
    expect(pushMock).toHaveBeenCalledWith("/us/en/combined-payment/pcom_1");
  });

  // PALLAS-CUSTOM (2026-08-29, bugfix): 无购物车时 defaultPaymentMethodId 为空，
  // 勾选后按钮仍应可用（支付方式由服务端默认选择）。
  it("enables Pay selected without a cart payment method (server picks default)", async () => {
    const user = userEvent.setup();
    mockedCreate.mockResolvedValue({
      combination: { id: "pcom_2" },
    } as never);

    render(
      <OrderCombinedPay
        orders={[
          order(),
          order({ id: "order_2", number: "R2", display_amount_due: "$20.00" }),
        ]}
        basePath="/us/en"
      />,
    );

    const button = screen.getByRole("button", { name: "paySelected" });
    expect(button).toBeDisabled();

    await user.click(screen.getAllByRole("checkbox")[0]);
    await user.click(screen.getAllByRole("checkbox")[1]);
    expect(button).toBeEnabled();

    await user.click(button);
    expect(mockedCreate).toHaveBeenCalledWith(["order_1", "order_2"], undefined);
    expect(pushMock).toHaveBeenCalledWith("/us/en/combined-payment/pcom_2");
  });
});
