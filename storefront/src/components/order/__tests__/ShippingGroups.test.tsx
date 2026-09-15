import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ShippingGroups } from "@/components/order/ShippingGroups";

vi.mock("next-intl", () => ({
  // 断言 key（与既有组件测试同口径）
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

const items = [
  { id: "li_1", name: "Product A", quantity: 1 },
  { id: "li_2", name: "Product B", quantity: 2 },
];

const twoFulfillments = [
  {
    id: "ful_1",
    display_cost: "$5.00",
    delivery_method: { name: "Standard Shipping" },
    items: [{ item_id: "li_1", quantity: 1 }],
  },
  {
    id: "ful_2",
    display_cost: "$0.00",
    delivery_method: { name: "Free Shipping" },
    items: [{ item_id: "li_2", quantity: 2 }],
  },
];

/**
 * 订单履约分组（PRD-20260915-checkout B3 FR-005，方案 §37）：
 * 多个 fulfillment → 按 Shipment 分组展示「哪个商品走哪一趟」；
 * 单个 → 退化为单列表（无分组标题）；悬空 item 引用静默降级。
 */
describe("ShippingGroups", () => {
  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-005
  it("groups items per shipment when there are several fulfillments", () => {
    render(<ShippingGroups items={items} fulfillments={twoFulfillments} />);

    expect(screen.getAllByTestId("shipping-group")).toHaveLength(2);
    expect(screen.getAllByTestId("shipping-group-title")).toHaveLength(2);
    expect(screen.getByText('shipment:{"index":1}')).toBeTruthy();
    expect(screen.getByText('shipment:{"index":2}')).toBeTruthy();

    expect(screen.getByText(/Product A/)).toBeTruthy();
    expect(screen.getByText(/Product B/)).toBeTruthy();
    expect(screen.getByText(/Standard Shipping/)).toBeTruthy();
    expect(screen.getByText(/Free Shipping/)).toBeTruthy();
    expect(screen.getByText(/\$5\.00/)).toBeTruthy();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-005
  it("renders one un-titled delivery row for a single fulfillment", () => {
    render(
      <ShippingGroups items={items} fulfillments={[twoFulfillments[0]]} />,
    );

    expect(screen.getAllByTestId("shipping-group")).toHaveLength(1);
    expect(screen.queryByTestId("shipping-group-title")).toBeNull();
    expect(screen.getByTestId("shipping-delivery").textContent).toContain(
      "Standard Shipping",
    );
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-010
  it("degrades when a fulfillment references an unknown line item", () => {
    render(
      <ShippingGroups
        items={items}
        fulfillments={[
          {
            id: "ful_1",
            delivery_method: { name: "Standard Shipping" },
            items: [{ item_id: "li_missing", quantity: 1 }],
          },
          twoFulfillments[1],
        ]}
      />,
    );

    // 只有能解析到的商品被渲染；悬空引用既不崩溃也不出现 undefined
    expect(screen.getAllByTestId("shipping-item")).toHaveLength(1);
    expect(screen.getByText(/Product B/)).toBeTruthy();
    expect(screen.queryByText(/undefined/)).toBeNull();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-009
  it("renders nothing without fulfillments", () => {
    const { container } = render(
      <ShippingGroups items={items} fulfillments={[]} />,
    );

    expect(container).toBeEmptyDOMElement();
  });
});
