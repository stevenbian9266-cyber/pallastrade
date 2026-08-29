"use client";

import type { Order } from "@pallastrade/sdk";
import { Loader2, Wallet } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { createPaymentCombination } from "@/lib/data/payment-combination";
import { extractBasePath } from "@/lib/utils/path";

interface OrderCombinedPayProps {
  orders: Order[];
  basePath: string;
  /** Default session payment method id (from the customer's cart), may be empty */
  defaultPaymentMethodId?: string;
}

/**
 * 账户订单多选 → 合并支付（P5, 2026-08-27，flag 灰度）。
 * 仅显示待支付（balance_due）且非子订单（is_child）的订单。
 */
export function OrderCombinedPay({
  orders,
  basePath,
  defaultPaymentMethodId = "",
}: OrderCombinedPayProps) {
  const t = useTranslations("orders");
  const router = useRouter();
  const pathname = usePathname();
  const extractedBasePath = extractBasePath(pathname);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [processing, setProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // 可合并的待支付订单（排除已付/子订单）
  const payable = useMemo(
    () =>
      orders.filter(
        (order) =>
          order.payment_status === "balance_due" &&
          !order.is_child &&
          Number(order.amount_due) > 0,
      ),
    [orders],
  );

  // PALLAS-CUSTOM (2026-08-29, bugfix): 不再依赖 defaultPaymentMethodId——
  // 用户可能没有购物车（getCart 返回空），此前导致按钮永远灰色。
  // 支付方式缺省时由服务端选择（payment_combinations API 的 payment_method_id 已可选）。
  const canPay = payable.length > 0 && selected.size > 0;

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function handleCombinedPay() {
    if (!canPay) return;
    setProcessing(true);
    setError(null);
    const result = await createPaymentCombination(
      Array.from(selected),
      defaultPaymentMethodId || undefined,
    );
    if ("error" in result) {
      setError(result.error);
      setProcessing(false);
      return;
    }
    // 跳转合并支付收银台
    router.push(
      `${extractedBasePath}/combined-payment/${result.combination.id}`,
    );
  }

  if (payable.length === 0) return null;

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-2">
          <Wallet className="h-4 w-4 text-gray-500" />
          <p className="text-sm text-gray-700">
            {t("combinedPayHint", { count: payable.length })}
          </p>
        </div>
        <Button
          onClick={handleCombinedPay}
          disabled={!canPay || processing}
          size="sm"
        >
          {processing ? (
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
          ) : null}
          {t("paySelected")}
        </Button>
      </div>

      {payable.length > 0 ? (
        <div className="mt-3 space-y-1">
          {payable.map((order) => (
            <label
              key={order.id}
              className="flex items-center gap-3 rounded-md px-2 py-1.5 hover:bg-gray-50 cursor-pointer"
            >
              <Checkbox
                checked={selected.has(order.id)}
                onCheckedChange={() => toggle(order.id)}
                aria-label={`${t("selectOrder")} #${order.number}`}
              />
              <span className="text-sm text-gray-700">#{order.number}</span>
              <span className="ml-auto text-sm font-medium text-gray-900">
                {order.display_amount_due}
              </span>
            </label>
          ))}
        </div>
      ) : null}

      {error ? (
        <p className="mt-2 text-sm text-red-600" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}
