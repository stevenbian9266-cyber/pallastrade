import Link from "next/link";

export type OrderStatusKey =
  | "all"
  | "unpaid"
  | "processing"
  | "shipped"
  | "completed"
  | "canceled";

interface OrderStatusTabsProps {
  tabs: Array<{ key: OrderStatusKey; label: string }>;
  activeKey: OrderStatusKey;
  basePath: string;
}

/**
 * PALLAS-CUSTOM: 订单状态选项卡（PRD-20260824-checkout-订单列表状态选项卡）—
 * 按状态切换订单列表，通过 ?status= 驱动服务端渲染。
 */
export function OrderStatusTabs({
  tabs,
  activeKey,
  basePath,
}: OrderStatusTabsProps) {
  return (
    <nav
      className="flex gap-2 mb-6 overflow-x-auto pb-1"
      aria-label="Order status"
      data-testid="order-status-tabs"
    >
      {tabs.map((tab) => {
        const active = tab.key === activeKey;
        return (
          <Link
            key={tab.key}
            href={
              tab.key === "all"
                ? `${basePath}/account/orders`
                : `${basePath}/account/orders?status=${tab.key}`
            }
            aria-current={active ? "page" : undefined}
            data-testid={`order-tab-${tab.key}`}
            className={`whitespace-nowrap rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
              active
                ? "bg-gray-900 text-white"
                : "bg-white text-gray-700 border border-gray-200 hover:bg-gray-50"
            }`}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
