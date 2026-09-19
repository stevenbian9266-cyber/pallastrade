import type { Order } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { OrderPayButton } from "@/components/account/OrderPayButton";

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

// PRD-20260919-checkout-结算页待支付订单再次支付重验-失效行剔除-优惠复核-订单金额变化提示-收银台弹窗退役 AC-010
// 补付入口**跳订单支付页**（收银台弹窗已退役）；可支付判定改金额权威。
describe("OrderPayButton (PRD-20260919-checkout AC-010)", () => {
  it("links to the order payment page for a payable order", () => {
    render(<OrderPayButton order={order()} basePath="/us/en" />);

    const link = screen.getByTestId("order-pay-link");
    expect(link).toBeInTheDocument();
    expect(link).toHaveAttribute("href", "/us/en/checkout/order_1");
  });

  it("renders even when payment_status is null (amount is the authority)", () => {
    render(
      <OrderPayButton
        order={order({ payment_status: null as unknown as string })}
        basePath="/us/en"
      />,
    );

    expect(screen.getByTestId("order-pay-link")).toBeInTheDocument();
  });

  it("does not render for paid / child / zero-due / completed orders", () => {
    const { rerender } = render(
      <OrderPayButton
        order={order({ payment_status: "paid" })}
        basePath="/us/en"
      />,
    );
    expect(screen.queryByTestId("order-pay-link")).not.toBeInTheDocument();

    rerender(
      <OrderPayButton order={order({ is_child: true })} basePath="/us/en" />,
    );
    expect(screen.queryByTestId("order-pay-link")).not.toBeInTheDocument();

    rerender(
      <OrderPayButton order={order({ amount_due: "0" })} basePath="/us/en" />,
    );
    expect(screen.queryByTestId("order-pay-link")).not.toBeInTheDocument();

    rerender(
      <OrderPayButton
        order={order({ completed_at: "2026-09-19T00:00:00Z" })}
        basePath="/us/en"
      />,
    );
    expect(screen.queryByTestId("order-pay-link")).not.toBeInTheDocument();
  });
});
