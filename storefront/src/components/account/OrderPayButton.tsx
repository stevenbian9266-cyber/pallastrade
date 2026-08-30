"use client";

import type { Order } from "@pallastrade/sdk";
import { CreditCard } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { PaymentCheckoutModal } from "@/components/checkout/PaymentCheckoutModal";
import { Button } from "@/components/ui/button";

interface OrderPayButtonProps {
  order: Order;
  basePath: string;
}

/**
 * 下单链路统一化（PRD-20260830-checkout，AC-007）：订单详情页 Pay Now。
 * 仅待支付（balance_due）且非子订单（is_child）显示 → 打开收银台弹窗。
 */
export function OrderPayButton({ order, basePath }: OrderPayButtonProps) {
  const t = useTranslations("orders");
  const [open, setOpen] = useState(false);

  const payable =
    order.payment_status === "balance_due" &&
    !order.is_child &&
    Number(order.amount_due) > 0;

  if (!payable) return null;

  return (
    <>
      <Button size="sm" onClick={() => setOpen(true)}>
        <CreditCard className="mr-2 h-4 w-4" />
        {t("payNow")}
      </Button>
      <PaymentCheckoutModal
        open={open}
        onOpenChange={setOpen}
        orders={[order]}
        basePath={basePath}
      />
    </>
  );
}
