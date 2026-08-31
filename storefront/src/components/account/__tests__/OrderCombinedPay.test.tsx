import type { Order } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { OrderCombinedPay } from "@/components/account/OrderCombinedPay";

// Mock PaymentCheckoutModal：仅暴露 props 供断言
const modalProps = vi.fn();
vi.mock("@/components/checkout/PaymentCheckoutModal", () => ({
  PaymentCheckoutModal: (props: Record<string, unknown>) => {
    modalProps(props);
    return props.open ? <div data-testid="checkout-modal" /> : null;
  },
}));

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

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

describe("OrderCombinedPay (场景 C：收银台弹窗, PRD-20260830-checkout)", () => {
  beforeEach(() => {
    modalProps.mockReset();
  });

  it("renders only payable (balance_due, non-child) orders (P5 AC-007)", () => {
    render(
      <OrderCombinedPay
        orders={[order(), order({ id: "order_2", payment_status: "paid" })]}
        basePath="/us/en"
      />,
    );

    expect(screen.getByText("#R1")).toBeInTheDocument();
    expect(screen.queryByText("#R2")).not.toBeInTheDocument();
  });

  // AC-005：勾选 1 笔 → 打开单笔收银台弹窗（不再跳 /checkout）
  it("opens the single-order checkout modal for one selected order (AC-005)", async () => {
    const user = userEvent.setup();

    render(<OrderCombinedPay orders={[order()]} basePath="/us/en" />);

    await user.click(screen.getByRole("checkbox"));
    await user.click(screen.getByRole("button", { name: "paySelected" }));

    expect(screen.getByTestId("checkout-modal")).toBeInTheDocument();
    const props = modalProps.mock.calls.at(-1)?.[0];
    expect(props.orders).toHaveLength(1);
    expect(props.orders[0].id).toBe("order_1");
  });

  // AC-006：勾选 2+ 笔 → 打开组合收银台弹窗（组合逻辑在弹窗内）
  it("opens the combination modal for multiple selected orders (AC-006)", async () => {
    const user = userEvent.setup();

    render(
      <OrderCombinedPay
        orders={[
          order(),
          order({ id: "order_2", number: "R2", display_amount_due: "$20.00" }),
        ]}
        basePath="/us/en"
      />,
    );

    await user.click(screen.getAllByRole("checkbox")[0]);
    await user.click(screen.getAllByRole("checkbox")[1]);
    await user.click(screen.getByRole("button", { name: "paySelected" }));

    expect(screen.getByTestId("checkout-modal")).toBeInTheDocument();
    const props = modalProps.mock.calls.at(-1)?.[0];
    expect(props.orders.map((o: Order) => o.id)).toEqual([
      "order_1",
      "order_2",
    ]);
  });

  it("enables Pay selected without loading a cart payment method", async () => {
    const user = userEvent.setup();

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
    expect(screen.getByTestId("checkout-modal")).toBeInTheDocument();
  });
});
