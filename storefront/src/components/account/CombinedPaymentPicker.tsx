"use client";

import type { Order } from "@pallastrade/sdk";
import { CircleAlert, Loader2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { createPaymentGroup } from "@/lib/data/payment-groups";

/**
 * PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
 * Lets the customer select multiple unpaid orders and pay them together.
 */
interface CombinedPaymentPickerProps {
  orders: Order[];
  basePath: string;
}

export function CombinedPaymentPicker({
  orders,
  basePath,
}: CombinedPaymentPickerProps) {
  const t = useTranslations("orders");
  const router = useRouter();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggle = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  };

  const payNow = async () => {
    if (selected.size === 0 || loading) return;
    setLoading(true);
    setError(null);

    const result = await createPaymentGroup([...selected]);
    setLoading(false);

    if (!result.success) {
      setError(result.error || t("combinedPayFailed"));
      return;
    }
    if (!result.group) {
      setError(t("combinedPayFailed"));
      return;
    }

    router.push(`${basePath}/account/combined-payment/${result.group.id}`);
  };

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-6 mb-6">
      <h2 className="text-lg font-medium text-gray-900 mb-1">
        {t("pendingPayment")}
      </h2>
      <p className="text-sm text-gray-500 mb-4">
        {t("pendingPaymentDescription")}
      </p>

      {orders.length === 0 ? (
        <p className="text-sm text-gray-500">{t("noPendingPayment")}</p>
      ) : (
        <>
          <ul className="divide-y divide-gray-100">
            {orders.map((order) => (
              <li key={order.id} className="py-3 flex items-center gap-3">
                <Checkbox
                  id={`combined-${order.id}`}
                  checked={selected.has(order.id)}
                  onCheckedChange={() => toggle(order.id)}
                />
                <label
                  htmlFor={`combined-${order.id}`}
                  className="flex-1 cursor-pointer flex items-center justify-between text-sm"
                >
                  <span className="font-medium text-gray-900">
                    #{order.number}
                  </span>
                  <span className="text-gray-500">
                    {order.currency} {order.total}
                  </span>
                </label>
              </li>
            ))}
          </ul>

          <div className="mt-4 flex items-center justify-between gap-4">
            <p className="text-sm text-gray-600">
              {t("selectedCount", { count: selected.size })}
            </p>
            <Button
              onClick={payNow}
              disabled={selected.size === 0 || loading}
              data-testid="combined-pay-button"
            >
              {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              {t("payTogether")}
            </Button>
          </div>
        </>
      )}

      {error && (
        <Alert variant="destructive" className="mt-4">
          <CircleAlert />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
