"use client";

import type { PaymentGroup, PaymentMethod } from "@pallastrade/sdk";
import { CircleAlert, Loader2, ShieldCheck } from "lucide-react";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  StripePaymentForm,
  type StripePaymentFormHandle,
} from "@/components/checkout/StripePaymentForm";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
  completeGroupPaymentSession,
  createGroupPaymentSession,
  getPaymentGroup,
} from "@/lib/data/payment-groups";
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
  const [error, setError] = useState<string | null>(null);
  const [processing, setProcessing] = useState(false);
  const [paid, setPaid] = useState(false);
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const stripeFormRef = useRef<StripePaymentFormHandle | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [groupResult, methodsResult] = await Promise.all([
        getPaymentGroup(groupId, { expand: ["orders"] }),
        getPaymentMethods(),
      ]);
      if (cancelled) return;
      if (!groupResult.success) {
        setError(groupResult.error || t("loadFailed"));
        return;
      }
      setGroup(groupResult.group);
      setPaymentMethods(methodsResult);
    })();
    return () => {
      cancelled = true;
    };
  }, [groupId, t]);

  const orders = group?.orders ?? [];

  const total = orders.reduce((sum: number, order) => {
    return sum + (parseFloat(order.total ?? "0") || 0);
  }, 0);

  const stripeMethod =
    paymentMethods.find((pm) => pm.session_required) ?? null;

  const startPayment = useCallback(async () => {
    if (!stripeMethod) return;
    setError(null);
    setProcessing(true);
    const result = await createGroupPaymentSession(groupId, stripeMethod.id);
    setProcessing(false);
    if (!result.success) {
      setError(result.error || t("payFailed"));
      return;
    }
    const secret = result.session.external_data?.client_secret as
      | string
      | undefined;
    if (!secret) {
      setError(t("payFailed"));
      return;
    }
    setClientSecret(secret);
    setSessionId(result.session.id);
  }, [groupId, stripeMethod, t]);

  const confirmPayment = useCallback(async () => {
    if (!stripeFormRef.current || !sessionId) return;
    setProcessing(true);
    setError(null);

    const result = await stripeFormRef.current.confirmPayment(
      `${basePath}/account/combined-payment/${groupId}`,
    );

    if (result.error) {
      setError(result.error);
      setProcessing(false);
      return;
    }

    const complete = await completeGroupPaymentSession(groupId, sessionId);
    setProcessing(false);

    if (!complete.success) {
      setError(complete.error || t("payFailed"));
      return;
    }
    setPaid(true);
  }, [basePath, groupId, sessionId, t]);

  if (paid) {
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

      {/* Payment */}
      <div className="bg-white rounded-xl border border-gray-200 p-6">
        {!clientSecret ? (
          <>
            <p className="text-sm text-gray-600 mb-4">
              {t("selectPaymentMethod")}
            </p>
            {stripeMethod ? (
              <Button
                onClick={startPayment}
                disabled={processing}
                data-testid="start-combined-payment"
              >
                {processing && (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                )}
                {t("pay")}
              </Button>
            ) : (
              <p className="text-sm text-gray-500">{t("noPaymentMethod")}</p>
            )}
          </>
        ) : (
          <>
            <StripePaymentForm
              clientSecret={clientSecret}
              onReady={(handle) => {
                stripeFormRef.current = handle;
              }}
            />
            <Button
              className="mt-4 w-full"
              onClick={confirmPayment}
              disabled={processing}
              data-testid="confirm-combined-payment"
            >
              {processing && (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              )}
              {t("confirmPay")}
            </Button>
          </>
        )}

        {error && (
          <Alert variant="destructive" className="mt-4">
            <CircleAlert />
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
      </div>
    </div>
  );
}
