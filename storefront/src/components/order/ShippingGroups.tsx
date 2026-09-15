"use client";

import { Package } from "lucide-react";
import { useTranslations } from "next-intl";

/**
 * 订单履约分组（PRD-20260915-checkout B3 FR-005，方案 §37）。
 *
 * 数据来自 Store API 契约里既有的 `fulfillments[]`：
 * - 每个 fulfillment 携带 `items[{ item_id, quantity }]` 与 `delivery_method`；
 * - 多履约（拆单 / 多仓）→ 按 Shipment 分组列出「哪个商品走哪一趟」；
 * - 单履约 → 退化为单列表且**不渲染分组标题**（避免无意义的 “Shipment 1”）；
 * - 找不到对应 line item 的条目直接跳过（降级，不渲染 undefined）。
 *
 * 组件只做展示：不做金额计算，也不推断库存/履约状态（服务端权威）。
 */

interface ShippingItem {
  id: string;
  name: string;
  quantity: number;
}

interface ShippingFulfillment {
  id: string;
  display_cost?: string | null;
  delivery_method?: { name?: string | null } | null;
  items?: Array<{ item_id: string; quantity: number }> | null;
}

interface ShippingGroupsProps {
  items: ShippingItem[];
  fulfillments: ShippingFulfillment[];
}

export function ShippingGroups({ items, fulfillments }: ShippingGroupsProps) {
  const t = useTranslations("order");

  const groups = (fulfillments ?? []).map((fulfillment, index) => {
    const byId = new Map(items.map((item) => [item.id, item]));
    const lines = (fulfillment.items ?? []).flatMap((entry) => {
      const item = byId.get(entry.item_id);
      if (!item) return [];
      return [{ item, quantity: entry.quantity }];
    });
    return { fulfillment, index, lines };
  });

  if (groups.length === 0) return null;

  const multiple = groups.length > 1;

  return (
    <div className="space-y-4" data-testid="shipping-groups">
      {groups.map(({ fulfillment, index, lines }) => (
        <div key={fulfillment.id} data-testid="shipping-group">
          {multiple ? (
            <p
              className="text-sm font-semibold text-gray-900"
              data-testid="shipping-group-title"
            >
              {t("shipment", { index: index + 1 })}
            </p>
          ) : null}

          {multiple && lines.length > 0 ? (
            <ul className="mt-2 space-y-1">
              {lines.map(({ item, quantity }) => (
                <li
                  key={item.id}
                  className="text-sm text-gray-700"
                  data-testid="shipping-item"
                >
                  {item.name} · {t("qty", { quantity })}
                </li>
              ))}
            </ul>
          ) : null}

          <p
            className="mt-2 flex items-center gap-2 text-sm text-gray-700"
            data-testid="shipping-delivery"
          >
            <Package className="h-4 w-4 shrink-0 text-gray-400" />
            <span>
              {fulfillment.delivery_method?.name ?? t("deliveryFallback")}
              {fulfillment.display_cost ? ` · ${fulfillment.display_cost}` : ""}
            </span>
          </p>
        </div>
      ))}
    </div>
  );
}
