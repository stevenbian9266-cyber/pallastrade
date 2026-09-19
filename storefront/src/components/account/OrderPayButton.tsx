"use client";

import type { Order } from "@pallastrade/sdk";
import { CreditCard } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { isOrderPayable } from "@/lib/account/order-payable";

interface OrderPayButtonProps {
  order: Order;
  basePath: string;
}

/**
 * 待支付订单补付入口（PRD-20260919-checkout FR-012）。
 *
 * 行为变更（2026-09-19）：**不再打开收银台弹窗**（`PaymentCheckoutModal` 已退役），
 * 而是跳「订单支付页」`/{country}/{locale}/checkout/{or_id}` —— 与「已转换购物车
 * 恢复」同一落点（`lib/checkout/recovery.ts`）；该页在支付前做一次商业事实重验
 * （失效商品剔除 / 价格与配送复核 / 金额变化提示），用户看到金额后直接支付。
 *
 * 可支付判定 = 金额权威（`isOrderPayable`），不再依赖 `payment_status`。
 */
export function OrderPayButton({ order, basePath }: OrderPayButtonProps) {
  const t = useTranslations("orders");

  if (!isOrderPayable(order)) return null;

  return (
    <Button size="sm" asChild>
      <Link
        href={`${basePath}/checkout/${order.id}`}
        data-testid="order-pay-link"
      >
        <CreditCard className="mr-2 h-4 w-4" />
        {t("payNow")}
      </Link>
    </Button>
  );
}
