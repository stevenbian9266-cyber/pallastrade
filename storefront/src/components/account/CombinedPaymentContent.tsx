"use client";

import type { PaymentGroup, PaymentMethod } from "@pallastrade/sdk";
import { CircleAlert, ShieldCheck } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { GroupPaymentForm } from "@/components/checkout/GroupPaymentForm";
import { Button } from "@/components/ui/button";
import { getPaymentGroup } from "@/lib/data/payment-groups";
import { getPaymentMethods } from "@/lib/data/payment-methods";

/**
 * PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
 * Renders the combined payment page: order list + total, then a Stripe
 * Elements form for one payment covering all orders in the group.
 */
interface CombinedPaymentContentProps {
  groupId: string;
  basePath: string;
}

export function CombinedPaymentContent({
  groupId,
  basePath,
}: CombinedPaymentContentProps) {
  const t = useTranslations("combinedPayment");
  const [group, setGroup] = useState<PaymentGroup | null>(null);
  const [paymentMethods, setPaymentMethods] = useState<PaymentMethod[]>([]);
  const [paid, setPaid] = useState(false);
  const loadedRef = useRef(false);

  useEffect(() => {
    if (loadedRef.current) return;
    loadedRef.current = true;
    let cancelled = false;
    (async () => {
      const [groupResult, methodsResult] = await Promise.all([
        getPaymentGroup(groupId, { expand: ["orders"] }),
        getPaymentMethods(),
      ]);
      if (cancelled) return;
      if (groupResult.success) {
        setGroup(groupResult.group);
        setPaymentMethods(methodsResult);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [groupId]);

  const orders = group?.orders ?? [];

  const total = orders.reduce((sum: number, order) => {
    return sum + (parseFloat(order.total ?? "0") || 0);
  }, 0);

  if (paid || group?.status === "completed") {
    return (
      <div className="bg-white rounded-xl border border-gray-200 p-8 text-center">
        <ShieldCheck className="w-12 h-12 text-green-600 mx-auto mb-4" />
        <h2 className="text-xl font-medium text-gray-900 mb-2">
          {t("paymentSuccess")}
        </h2>
        <p className="text-gray-500 mb-6">{t("paymentSuccessDescription")}</p>
        <Button asChild>
          <Link href={`${basePath}/account/orders`}>{t("backToOrders")}</Link>
        </Button>
      </div>
    );
  }

  // PALLAS-CUSTOM: 处理非激活支付组（2026-08-24）— failed/expired/canceled 组
  // 不允许再支付，展示明确状态，不再抛状态机裸错误（后端 Complete 已容错）。
  if (group?.status === "failed") {
    return (
      <div className="bg-white rounded-xl border border-gray-200 p-8 text-center">
        <CircleAlert className="w-12 h-12 text-red-600 mx-auto mb-4" />
        <h2 className="text-xl font-medium text-gray-900 mb-2">
          {t("groupFailed")}
        </h2>
        <p className="text-gray-500 mb-6">{t("groupFailedDescription")}</p>
        <Button asChild variant="outline">
          <Link href={`${basePath}/account/orders`}>{t("backToOrders")}</Link>
        </Button>
      </div>
    );
  }

  if (group?.status === "canceled" || group?.status === "expired") {
    return (
      <div className="bg-white rounded-xl border border-gray-200 p-8 text-center">
        <CircleAlert className="w-12 h-12 text-amber-500 mx-auto mb-4" />
        <h2 className="text-xl font-medium text-gray-900 mb-2">
          {t("groupEnded")}
        </h2>
        <p className="text-gray-500 mb-6">{t("groupEndedDescription")}</p>
        <Button asChild variant="outline">
          <Link href={`${basePath}/account/orders`}>{t("backToOrders")}</Link>
        </Button>
      </div>
    );
  }

  if (!group) {
    return (
      <div className="space-y-6">
        <div className="bg-white rounded-xl border border-gray-200 p-6 animate-pulse">
          <div className="h-4 bg-gray-200 rounded w-1/3 mb-4" />
          <div className="h-4 bg-gray-200 rounded w-1/2" />
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Order summary */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-100">
          <h2 className="font-medium text-gray-900">{t("orders")}</h2>
        </div>
        <ul className="divide-y divide-gray-100">
          {orders.map((order) => (
            <li
              key={order.id}
              className="px-6 py-3 flex items-center justify-between text-sm"
            >
              <span className="font-medium text-gray-900">#{order.number}</span>
              <span className="text-gray-500">
                {order.currency} {order.total}
              </span>
            </li>
          ))}
        </ul>
        <div className="px-6 py-4 bg-gray-50 flex items-center justify-between">
          <span className="font-medium text-gray-900">{t("total")}</span>
          <span className="font-bold text-gray-900">
            {group?.currency} {total.toFixed(2)}
          </span>
        </div>
      </div>

      {/* PALLAS-CUSTOM: 公用收银台（PRD-20260824 FR-013）— 单订单付款与多订单合并支付
          复用同一 GroupPaymentForm（payment group 语义，单订单也走 1 订单支付组）。
          支付错误由 GroupPaymentForm 内部 Alert 展示。 */}
      <GroupPaymentForm
        groupId={groupId}
        basePath={basePath}
        paymentMethods={paymentMethods}
        onPaid={() => setPaid(true)}
      />
    </div>
  );
}
