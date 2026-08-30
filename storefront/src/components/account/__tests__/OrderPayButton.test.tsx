import type { Order } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { OrderPayButton } from "@/components/account/OrderPayButton";

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

describe("OrderPayButton (PRD-20260830-checkout AC-007)", () => {
  beforeEach(() => {
    modalProps.mockReset();
  });

  it("shows Pay Now for a payable order and opens the checkout modal", async () => {
    const user = userEvent.setup();
    render(<OrderPayButton order={order()} basePath="/us/en" />);

    const button = screen.getByRole("button", { name: "payNow" });
    expect(button).toBeInTheDocument();

    await user.click(button);
    expect(screen.getByTestId("checkout-modal")).toBeInTheDocument();
    const props = modalProps.mock.calls.at(-1)?.[0];
    expect(props.orders[0].id).toBe("order_1");
  });

  it("does not render for paid / child / zero-due orders", () => {
    const { rerender } = render(
      <OrderPayButton
        order={order({ payment_status: "paid" })}
        basePath="/us/en"
      />,
    );
    expect(
      screen.queryByRole("button", { name: "payNow" }),
    ).not.toBeInTheDocument();

    rerender(
      <OrderPayButton order={order({ is_child: true })} basePath="/us/en" />,
    );
    expect(
      screen.queryByRole("button", { name: "payNow" }),
    ).not.toBeInTheDocument();

    rerender(
      <OrderPayButton order={order({ amount_due: "0" })} basePath="/us/en" />,
    );
    expect(
      screen.queryByRole("button", { name: "payNow" }),
    ).not.toBeInTheDocument();
  });
});
